\set ON_ERROR_STOP on
begin;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if not condition then raise exception 'ASSERTION FAILED: %', message; end if; end $$;

create or replace function pg_temp.seed_published_product_batch(
  p_user_id uuid,
  p_contract_id uuid,
  p_source_kind text,
  p_scope_key text,
  p_rows jsonb,
  p_hash_seed text
) returns uuid
language plpgsql
as $$
declare
  v_batch uuid := gen_random_uuid();
  v_chunk uuid := gen_random_uuid();
  v_validation uuid := gen_random_uuid();
  v_reconciliation uuid := gen_random_uuid();
  v_candidate uuid := gen_random_uuid();
  v_publication uuid := gen_random_uuid();
  v_row_count integer := jsonb_array_length(p_rows);
  v_version integer;
begin
  insert into public.import_batches(
    id, source_contract_version_id, source_kind, scope_key, source_sheet, source_headers,
    storage_object_path, declared_file_hash, verified_file_hash, file_size_bytes,
    expected_rows, expected_chunks, received_chunks, staged_rows, expected_control_totals,
    status, source_verified_at, created_by
  )
  select
    v_batch, p_contract_id, p_source_kind, p_scope_key, sc.required_sheet, sc.required_headers,
    'imports/' || v_batch::text || '/source.xlsx', repeat(substr(p_hash_seed,1,1),64), repeat(substr(p_hash_seed,1,1),64), 1,
    v_row_count, 1, 1, v_row_count, '{}'::jsonb,
    'PUBLISHED'::public.import_batch_status, now(), p_user_id
  from public.source_contract_versions sc where sc.id = p_contract_id;

  insert into public.import_chunks(id,batch_id,chunk_no,row_offset,chunk_hash,server_chunk_hash,row_count)
  values (v_chunk,v_batch,0,0,repeat(substr(p_hash_seed,1,1),64),repeat(substr(p_hash_seed,1,1),64),v_row_count);

  insert into public.staging_rows(batch_id,chunk_id,source_row_no,payload,payload_hash,row_status)
  select v_batch, v_chunk, item.ordinality, item.value, encode(extensions.digest(convert_to(item.value::text,'UTF8'),'sha256'),'hex'), 'VALID'::public.staging_row_status
  from jsonb_array_elements(p_rows) with ordinality item(value, ordinality);

  insert into public.validation_runs(id,batch_id,contract_version_id,valid_rows,status)
  values (v_validation,v_batch,p_contract_id,v_row_count,'PASSED');
  insert into public.import_reconciliations(id,batch_id,parsed_rows,valid_rows,excluded_rows,blocked_rows,duplicate_rows,expected_control_totals,actual_control_totals,status)
  values (v_reconciliation,v_batch,v_row_count,v_row_count,0,0,0,'{}','{}','MATCHED');
  insert into public.candidate_publications(id,batch_id,validation_run_id,reconciliation_id,manifest,status,created_by,published_at)
  values (v_candidate,v_batch,v_validation,v_reconciliation,jsonb_build_object('test',true),'PUBLISHED',p_user_id,now());

  select coalesce(max(version),0)+1 into v_version from public.publications where source_kind=p_source_kind and scope_key=p_scope_key;
  insert into public.publications(id,candidate_id,source_kind,scope_key,version,manifest,published_by,published_at)
  values (v_publication,v_candidate,p_source_kind,p_scope_key,v_version,jsonb_build_object('test',true),p_user_id,now());
  update public.import_batches set validation_run_id=v_validation,reconciliation_id=v_reconciliation,published_publication_id=v_publication,completed_at=now() where id=v_batch;
  insert into public.publication_heads(source_kind,scope_key,active_publication_id,version)
  values (p_source_kind,p_scope_key,v_publication,v_version)
  on conflict (source_kind,scope_key) do update set active_publication_id=excluded.active_publication_id,version=excluded.version,updated_at=now();
  return v_batch;
end;
$$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_viewer uuid := gen_random_uuid();
  v_conversion_contract uuid;
  v_sellout_contract uuid;
  v_ka_contract uuid;
  v_conversion_batch uuid;
  v_sellout_batch uuid;
  v_ka_batch uuid;
  v_bad_conversion_batch uuid;
  v_inconsistent_conversion_batch uuid;
  v_uom_conflict_batch uuid;
  v_wrong_scope_sellout_batch uuid;
  v_result jsonb;
  v_run uuid;
  v_old_product_head uuid;
  v_rejected boolean := false;
  v_factor_rejected boolean := false;
  v_uom_rejected boolean := false;
  v_scope_rejected boolean := false;
begin
  insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values
    (v_admin,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','p03-admin@example.test','x',now(),'{}','{}',now(),now()),
    (v_viewer,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','p03-viewer@example.test','x',now(),'{}','{}',now(),now());
  update public.user_profiles set role='admin' where user_id=v_admin;

  select id into v_conversion_contract from public.source_contract_versions where source_kind='PRODUCT_CONVERSION' and version='1' and is_active;
  select id into v_sellout_contract from public.source_contract_versions where source_kind='SELLOUT' and version='1' and is_active;
  select id into v_ka_contract from public.source_contract_versions where source_kind='KA_DELIVERY' and version='1' and is_active;

  perform pg_temp.assert_true(v_conversion_contract is not null and v_sellout_contract is not null and v_ka_contract is not null, 'Package 03 source contracts are active');
  perform pg_temp.assert_true(
    (select required_headers @> '["Üretim yeri","Miktar","Miktar__2"]'::jsonb from public.source_contract_versions where id=v_conversion_contract),
    'PRODUCT_CONVERSION contract preserves both duplicate Miktar columns'
  );

  v_conversion_batch := pg_temp.seed_published_product_batch(v_admin,v_conversion_contract,'PRODUCT_CONVERSION','P03-TEST',jsonb_build_array(
    jsonb_build_object('Üretim yeri','P03-TEST','Bozulan/Birleştirilen Ürün Kodu','100001','Miktar',1,'Temel ölçü birimi','KL','Oluşan Ürün Kodu','100002','Miktar__2',2,'Temel ölçü birimi__2','ADT'),
    jsonb_build_object('Üretim yeri','P03-TEST','Bozulan/Birleştirilen Ürün Kodu','100003','Miktar',1,'Temel ölçü birimi','KL','Oluşan Ürün Kodu','100004','Miktar__2',4,'Temel ölçü birimi__2','ADT')
  ),'a');

  v_sellout_batch := pg_temp.seed_published_product_batch(v_admin,v_sellout_contract,'SELLOUT','P03-TEST',jsonb_build_array(
    jsonb_build_object('Bayi/Distribütör','P03-TEST','Malzeme Kodu','100002','Malzeme Tnm.','Variant B','Mal Grubu Tnm.','Family One','Miktar',2,'Litre',1,'Faturalama Tarihi',46000),
    jsonb_build_object('Bayi/Distribütör','P03-TEST','Malzeme Kodu','100002','Malzeme Tnm.','Variant B','Mal Grubu Tnm.','Family One','Miktar',4,'Litre',2,'Faturalama Tarihi',46001),
    jsonb_build_object('Bayi/Distribütör','P03-TEST','Malzeme Kodu','225887','Malzeme Tnm.','Conflict Variant','Mal Grubu Tnm.','Family Conflict','Miktar',-5,'Litre',-1.18,'Faturalama Tarihi',46000),
    jsonb_build_object('Bayi/Distribütör','P03-TEST','Malzeme Kodu','225887','Malzeme Tnm.','Conflict Variant','Mal Grubu Tnm.','Family Conflict','Miktar',-48,'Litre',-11.37,'Faturalama Tarihi',46001),
    jsonb_build_object('Bayi/Distribütör','P03-TEST','Malzeme Kodu','100007','Malzeme Tnm.','Cross Verified','Mal Grubu Tnm.','Family Cross','Miktar',2,'Litre',1.2,'Faturalama Tarihi',46000)
  ),'b');

  v_ka_batch := pg_temp.seed_published_product_batch(v_admin,v_ka_contract,'KA_DELIVERY','P03-TEST',jsonb_build_array(
    jsonb_build_object('Bayi/Dist Kodu','P03-TEST','Ürün Kodu','100002','Malzeme kısa metni','Variant B','Litre',1,'Miktar',2,'Yükleme Tarihi',46000),
    jsonb_build_object('Bayi/Dist Kodu','P03-TEST','Ürün Kodu','100002','Malzeme kısa metni','Variant B','Litre',1.02,'Miktar',2,'Yükleme Tarihi',46001),
    jsonb_build_object('Bayi/Dist Kodu','P03-TEST','Ürün Kodu','100005','Malzeme kısa metni','KA Only','Litre',7.92,'Miktar',1,'Yükleme Tarihi',46000),
    jsonb_build_object('Bayi/Dist Kodu','P03-TEST','Ürün Kodu','100006','Malzeme kısa metni','KA Weighted','Litre',1.00,'Miktar',2,'Yükleme Tarihi',46000),
    jsonb_build_object('Bayi/Dist Kodu','P03-TEST','Ürün Kodu','100006','Malzeme kısa metni','KA Weighted','Litre',1.51,'Miktar',3,'Yükleme Tarihi',46001),
    jsonb_build_object('Bayi/Dist Kodu','P03-TEST','Ürün Kodu','100007','Malzeme kısa metni','Cross Verified','Litre',3,'Miktar',5,'Yükleme Tarihi',46000)
  ),'c');

  set local role authenticated;
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  v_result := public.materialize_current_product_domain('P03-TEST');
  v_run := (v_result->>'run_id')::uuid;

  perform pg_temp.assert_true((v_result->'summary'->>'variant_count')::bigint=8, 'union product universe materializes without duplicating raw source rows');
  perform pg_temp.assert_true((v_result->'summary'->>'directed_edge_count')::bigint=2, 'directed conversion edges are aggregated');
  perform pg_temp.assert_true(
    (v_result->'summary'->>'product_name_resolved')::bigint=5
    and (v_result->'summary'->>'product_name_partial')::bigint=3
    and (v_result->'summary'->>'product_name_blocked')::bigint=0,
    'product-name resolution states stay explicit'
  );
  perform pg_temp.assert_true(
    (select lpu=1 and lpu_source='CONVERSION_GRAPH' and lpu_resolution_state='RESOLVED' and lpu_verification_state='derived_pending'
      from public.product_variant_resolutions where run_id=v_run and product_code='100001'),
    'graph propagation resolves source variant LPU while retaining derived verification state'
  );
  perform pg_temp.assert_true(
    (select f.display_name='Family One' and r.family_source='CONVERSION_GRAPH' and r.family_resolution_state='RESOLVED'
     from public.product_variant_resolutions r join public.product_families f on f.id=r.family_id where r.run_id=v_run and r.product_code='100001'),
    'family propagates only through a verified conversion component'
  );
  perform pg_temp.assert_true(
    (select lpu=0.5 and lpu_source='SELLOUT' and lpu_resolution_state='RESOLVED'
      and sellout_lpu_candidate=0.5 and ka_lpu_candidate=0.505
      and lpu_source_variance=0.005 and lpu_verification_state='sellout_verified'
     from public.product_variant_resolutions where run_id=v_run and product_code='100002'),
    'positive Sellout aggregate remains authoritative while lower-priority KA variance stays visible'
  );
  perform pg_temp.assert_true(
    (select lpu=0.502 and lpu_source='KA_DELIVERY' and lpu_resolution_state='RESOLVED'
      and ka_lpu_candidate=0.502 and lpu_verification_state='ka_verified'
     from public.product_variant_resolutions where run_id=v_run and product_code='100006'),
    'KA LPU uses the binding weighted aggregate sum(litres)/sum(quantity), not row-ratio equality'
  );
  perform pg_temp.assert_true(
    (select lpu=0.6 and sellout_lpu_candidate=0.6 and ka_lpu_candidate=0.6
      and lpu_source='SELLOUT' and lpu_verification_state='cross_source_verified' and lpu_source_variance=0
     from public.product_variant_resolutions where run_id=v_run and product_code='100007'),
    'exact Sellout/KA aggregate agreement is explicitly cross-source verified'
  );
  perform pg_temp.assert_true(
    (select lpu=7.920000000 and lpu_source='KA_DELIVERY' and family_resolution_state='PARTIAL' from public.product_variant_resolutions where run_id=v_run and product_code='100005'),
    'stable KA resolves LPU while missing family remains partial rather than invented'
  );
  perform pg_temp.assert_true(
    (select lpu is null and lpu_resolution_state='PARTIAL' and family_resolution_state='PARTIAL' from public.product_variant_resolutions where run_id=v_run and product_code in ('100003','100004') limit 1),
    'unanchored conversion component remains partial and never becomes zero'
  );
  perform pg_temp.assert_true(
    (select lpu is null and lpu_resolution_state='PARTIAL' and lpu_source is null and lpu_verification_state='missing'
      and sellout_lpu_candidate is null
      and (resolution_evidence->'sellout'->>'positive_rows')::bigint=0
      and (resolution_evidence->'sellout'->>'return_rows')::bigint=2
     from public.product_variant_resolutions where run_id=v_run and product_code='225887'),
    'negative Sellout returns are not positive LPU evidence and therefore remain PARTIAL/null rather than becoming a false conflict'
  );
  perform pg_temp.assert_true(
    (select quantity_uom='KL' and quantity_uom_resolution_state='RESOLVED' and quantity_uom_source='PRODUCT_CONVERSION'
     from public.product_variant_resolutions where run_id=v_run and product_code='100001'),
    'conversion evidence resolves the product quantity UOM without guessing units-per-case or unit volume'
  );
  select active_run_id into v_old_product_head from public.product_domain_heads where scope_key='P03-TEST';

  -- Same publications are idempotent.
  v_result := public.materialize_current_product_domain('P03-TEST');
  perform pg_temp.assert_true((v_result->>'reused')::boolean and (v_result->>'run_id')::uuid=v_old_product_head, 'same source publications reuse the current product run');
  reset role;

  -- One product code cannot carry two quantity UOMs inside the conversion graph.
  -- Reject the new run and preserve the prior current head.
  v_uom_conflict_batch := pg_temp.seed_published_product_batch(v_admin,v_conversion_contract,'PRODUCT_CONVERSION','P03-TEST',jsonb_build_array(
    jsonb_build_object('Üretim yeri','P03-TEST','Bozulan/Birleştirilen Ürün Kodu','300001','Miktar',1,'Temel ölçü birimi','KL','Oluşan Ürün Kodu','300002','Miktar__2',2,'Temel ölçü birimi__2','ADT'),
    jsonb_build_object('Üretim yeri','P03-TEST','Bozulan/Birleştirilen Ürün Kodu','300001','Miktar',1,'Temel ölçü birimi','ADT','Oluşan Ürün Kodu','300003','Miktar__2',4,'Temel ölçü birimi__2','ADT')
  ),'0');
  set local role authenticated;
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  begin
    perform public.materialize_current_product_domain('P03-TEST');
  exception when check_violation then
    v_uom_rejected := true;
  end;
  perform pg_temp.assert_true(v_uom_rejected, 'conflicting quantity UOM evidence is rejected');
  perform pg_temp.assert_true((select active_run_id=v_old_product_head from public.product_domain_heads where scope_key='P03-TEST'), 'UOM failure keeps prior canonical product head');
  perform pg_temp.assert_true((select bool_and(valid_to is null) from public.product_variant_resolutions where run_id=v_old_product_head), 'UOM failure does not close prior product validity period');
  reset role;

  -- A conversion component with contradictory factor paths is unusable even
  -- when it has no direct LPU anchor. Reject it without replacing current truth.
  v_inconsistent_conversion_batch := pg_temp.seed_published_product_batch(v_admin,v_conversion_contract,'PRODUCT_CONVERSION','P03-TEST',jsonb_build_array(
    jsonb_build_object('Üretim yeri','P03-TEST','Bozulan/Birleştirilen Ürün Kodu','200001','Miktar',1,'Temel ölçü birimi','ADT','Oluşan Ürün Kodu','200002','Miktar__2',2,'Temel ölçü birimi__2','ADT'),
    jsonb_build_object('Üretim yeri','P03-TEST','Bozulan/Birleştirilen Ürün Kodu','200002','Miktar',1,'Temel ölçü birimi','ADT','Oluşan Ürün Kodu','200003','Miktar__2',2,'Temel ölçü birimi__2','ADT'),
    jsonb_build_object('Üretim yeri','P03-TEST','Bozulan/Birleştirilen Ürün Kodu','200001','Miktar',1,'Temel ölçü birimi','ADT','Oluşan Ürün Kodu','200003','Miktar__2',5,'Temel ölçü birimi__2','ADT')
  ),'f');
  set local role authenticated;
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  begin
    perform public.materialize_current_product_domain('P03-TEST');
  exception when check_violation then
    v_factor_rejected := true;
  end;
  perform pg_temp.assert_true(v_factor_rejected, 'internally inconsistent conversion factor paths are rejected without requiring an LPU anchor');
  perform pg_temp.assert_true((select active_run_id=v_old_product_head from public.product_domain_heads where scope_key='P03-TEST'), 'factor-path failure keeps prior canonical product head');
  perform pg_temp.assert_true((select bool_and(valid_to is null) from public.product_variant_resolutions where run_id=v_old_product_head), 'factor-path failure does not close prior product validity period');
  reset role;

  -- Publish a known rejected conversion mapping and prove materialization refuses it
  -- without replacing the prior canonical product-domain head.
  v_bad_conversion_batch := pg_temp.seed_published_product_batch(v_admin,v_conversion_contract,'PRODUCT_CONVERSION','P03-TEST',jsonb_build_array(
    jsonb_build_object('Üretim yeri','P03-TEST','Bozulan/Birleştirilen Ürün Kodu','154558','Miktar',1,'Temel ölçü birimi','KL','Oluşan Ürün Kodu','150003','Miktar__2',2,'Temel ölçü birimi__2','ADT')
  ),'d');

  set local role authenticated;
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  begin
    perform public.materialize_current_product_domain('P03-TEST');
  exception when check_violation then
    v_rejected := true;
  end;
  perform pg_temp.assert_true(v_rejected, 'known bad 154558/154559 -> 150003 mapping is rejected');
  perform pg_temp.assert_true((select active_run_id=v_old_product_head from public.product_domain_heads where scope_key='P03-TEST'), 'failed materialization keeps prior canonical product head');
  perform pg_temp.assert_true((select bool_and(valid_to is null) from public.product_variant_resolutions where run_id=v_old_product_head), 'failed materialization does not close prior product validity period');

  -- A manually declared batch scope cannot relabel rows whose workbook-carried
  -- distributor scope belongs somewhere else.
  reset role;
  v_wrong_scope_sellout_batch := pg_temp.seed_published_product_batch(v_admin,v_sellout_contract,'SELLOUT','P03-TEST',jsonb_build_array(
    jsonb_build_object('Bayi/Distribütör','OTHER-SCOPE','Malzeme Kodu','100002','Malzeme Tnm.','Variant B','Mal Grubu Tnm.','Family One','Miktar',2,'Litre',1,'Faturalama Tarihi',46002)
  ),'e');
  set local role authenticated;
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',v_admin::text,true);
  begin
    perform public.materialize_current_product_domain('P03-TEST');
  exception when invalid_parameter_value then
    v_scope_rejected := true;
  end;
  perform pg_temp.assert_true(v_scope_rejected, 'embedded source scope mismatch is rejected');
  perform pg_temp.assert_true((select active_run_id=v_old_product_head from public.product_domain_heads where scope_key='P03-TEST'), 'scope mismatch keeps prior canonical product head');
  perform pg_temp.assert_true((select bool_and(valid_to is null) from public.product_variant_resolutions where run_id=v_old_product_head), 'scope mismatch does not close prior product validity period');

  -- Admin raw/base access works.
  perform pg_temp.assert_true((select count(*)>0 from public.product_variant_resolutions where run_id=v_old_product_head), 'admin can read product resolution evidence');

  -- Viewer gets only the bounded business surface, not raw/base evidence tables.
  perform set_config('request.jwt.claim.sub',v_viewer::text,true);
  perform pg_temp.assert_true(
    (select count(*)=0 from public.product_domain_runs)
    and (select count(*)=0 from public.product_domain_heads)
    and (select count(*)=0 from public.product_conversion_edges)
    and (select count(*)=0 from public.product_families)
    and (select count(*)=0 from public.product_variant_resolutions)
    and (select count(*)=0 from public.product_variants),
    'viewer cannot read Package 03 base/provenance tables directly'
  );
  perform pg_temp.assert_true((select count(*)=8 from public.read_current_product_business_surface() where scope_key='P03-TEST'), 'viewer-safe product business surface remains readable');
  perform pg_temp.assert_true((select lpu is null and lpu_resolution_state='PARTIAL' and lpu_verification_state='missing' from public.read_current_product_business_surface() where scope_key='P03-TEST' and product_code='225887'), 'viewer surface preserves return-only missing/null LPU truth');
  perform pg_temp.assert_true(
    (select variant_count=8 and product_name_resolved=5 and product_name_partial=3 and product_name_blocked=0
      and lpu_resolved=5 and lpu_partial=3 and lpu_blocked=0
      and quantity_uom_resolved=4 and quantity_uom_partial=4 and quantity_uom_blocked=0
      and lpu_cross_source_compared=2 and lpu_source_variance_nonzero=1
      and lpu_cross_source_verified=1 and lpu_sellout_verified=1 and lpu_ka_verified=2 and lpu_derived_pending=1 and lpu_missing=3
     from public.read_current_product_domain_summary() where scope_key='P03-TEST'),
    'viewer-safe product summary exposes exact coverage and LPU source-variance state counts'
  );
  reset role;
end;
$$;

rollback;
