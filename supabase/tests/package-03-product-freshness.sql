\set ON_ERROR_STOP on
begin;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if not condition then raise exception 'ASSERTION FAILED: %', message; end if; end $$;

create or replace function pg_temp.create_and_publish_candidate(
  p_user_id uuid, p_contract_id uuid, p_source_kind text, p_scope_key text, p_rows jsonb, p_hash_char text
) returns uuid
language plpgsql
security definer
as $$
declare
  v_batch uuid := gen_random_uuid();
  v_chunk uuid := gen_random_uuid();
  v_validation uuid := gen_random_uuid();
  v_reconciliation uuid := gen_random_uuid();
  v_candidate uuid := gen_random_uuid();
  v_publication uuid;
  v_expected_head uuid;
  v_row_count integer := jsonb_array_length(p_rows);
begin
  insert into public.import_batches(
    id,source_contract_version_id,source_kind,scope_key,source_sheet,source_headers,
    storage_object_path,declared_file_hash,verified_file_hash,file_size_bytes,
    expected_rows,expected_chunks,received_chunks,staged_rows,expected_control_totals,
    status,source_verified_at,created_by
  )
  select v_batch,p_contract_id,p_source_kind,p_scope_key,sc.required_sheet,sc.required_headers,
    'imports/'||v_batch::text||'/source.xlsx',repeat(substr(p_hash_char,1,1),64),repeat(substr(p_hash_char,1,1),64),1,
    v_row_count,1,1,v_row_count,'{}'::jsonb,'VALIDATED'::public.import_batch_status,now(),p_user_id
  from public.source_contract_versions sc where sc.id=p_contract_id and sc.is_active;

  insert into public.import_chunks(id,batch_id,chunk_no,row_offset,chunk_hash,server_chunk_hash,row_count)
  values(v_chunk,v_batch,0,0,repeat(substr(p_hash_char,1,1),64),repeat(substr(p_hash_char,1,1),64),v_row_count);

  insert into public.staging_rows(batch_id,chunk_id,source_row_no,payload,payload_hash,row_status)
  select v_batch,v_chunk,item.ordinality,item.value,
    encode(extensions.digest(convert_to(item.value::text,'UTF8'),'sha256'),'hex'),'VALID'::public.staging_row_status
  from jsonb_array_elements(p_rows) with ordinality item(value,ordinality);

  insert into public.validation_runs(id,batch_id,contract_version_id,valid_rows,status)
  values(v_validation,v_batch,p_contract_id,v_row_count,'PASSED');
  insert into public.import_reconciliations(
    id,batch_id,parsed_rows,valid_rows,excluded_rows,blocked_rows,duplicate_rows,expected_control_totals,actual_control_totals,status
  ) values(v_reconciliation,v_batch,v_row_count,v_row_count,0,0,0,'{}','{}','MATCHED');
  update public.import_batches set status='CANDIDATE_READY',validation_run_id=v_validation,reconciliation_id=v_reconciliation where id=v_batch;
  insert into public.candidate_publications(id,batch_id,validation_run_id,reconciliation_id,manifest,status,created_by)
  values(v_candidate,v_batch,v_validation,v_reconciliation,jsonb_build_object('test',true),'READY',p_user_id);
  select active_publication_id into v_expected_head from public.publication_heads where source_kind=p_source_kind and scope_key=p_scope_key;
  v_publication := public.publish_candidate(v_candidate,v_expected_head);
  return v_publication;
end;
$$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_viewer uuid := gen_random_uuid();
  v_sellout_contract uuid;
  v_ka_contract uuid;
  v_head public.product_domain_heads;
  v_fresh record;
  v_lpu record;
  v_viewer_rejected boolean := false;
begin
  insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values
    (v_admin,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','p03-norm-admin@example.test','x',now(),'{}','{}',now(),now()),
    (v_viewer,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','p03-norm-viewer@example.test','x',now(),'{}','{}',now(),now());
  update public.user_profiles set role='admin' where user_id=v_admin;
  update public.user_profiles set role='viewer' where user_id=v_viewer;

  select id into v_sellout_contract from public.source_contract_versions where source_kind='SELLOUT' and version='1' and is_active;
  select id into v_ka_contract from public.source_contract_versions where source_kind='KA_DELIVERY' and version='1' and is_active;
  perform pg_temp.assert_true(v_sellout_contract is not null and v_ka_contract is not null, 'Sellout and KA runtime contracts remain active');
  perform pg_temp.assert_true(not exists(select 1 from public.source_contract_versions where source_kind='PRODUCT_CONVERSION' and is_active), 'paket upload contract stays retired');

  set local role authenticated;
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',v_admin::text,true);

  -- No runtime source yet: the static reference exists but freshness is pending.
  perform public.reconcile_product_domain_freshness('1237');
  select * into v_head from public.product_domain_heads where scope_key='1237';
  perform pg_temp.assert_true(v_head.freshness_state='PENDING_SOURCES' and v_head.active_run_id is null, 'static reference alone => PENDING_SOURCES');
  perform pg_temp.assert_true(v_head.expected_conversion_publication_id is null, 'freshness no longer depends on PRODUCT_CONVERSION publication');

  -- Traditional Sellout only => still pending.
  perform pg_temp.create_and_publish_candidate(
    v_admin,v_sellout_contract,'SELLOUT','1237',
    jsonb_build_array(jsonb_build_object(
      'Bayi/Distribütör','1237','Malzeme Kodu','154548','Malzeme Tnm.','Split Product','Mal Grubu Tnm.','Efes Pilsen',
      'Miktar','1','Litre','3','Faturalama Tarihi','2026-08-01'
    )),'a'
  );
  select * into v_head from public.product_domain_heads where scope_key='1237';
  perform pg_temp.assert_true(v_head.freshness_state='PENDING_SOURCES', 'Sellout without KA => PENDING_SOURCES');
  perform pg_temp.assert_true(v_head.expected_conversion_publication_id is null and v_head.expected_sellout_publication_id is not null, 'only runtime Sellout publication is tracked');

  -- Modern/KA source arrives => FRESH immediately; no paket upload/materialization is required.
  perform pg_temp.create_and_publish_candidate(
    v_admin,v_ka_contract,'KA_DELIVERY','1237',
    jsonb_build_array(jsonb_build_object(
      'Bayi/Dist Kodu','1237','Ürün Kodu','150021','Malzeme kısa metni','Main Product',
      'Litre','12','Miktar','1','Yükleme Tarihi','2026-08-01'
    )),'b'
  );
  select * into v_head from public.product_domain_heads where scope_key='1237';
  perform pg_temp.assert_true(v_head.freshness_state='FRESH' and v_head.active_run_id is null, 'Sellout + KA + static reference => FRESH without product run');
  perform pg_temp.assert_true(v_head.expected_conversion_publication_id is null and v_head.expected_sellout_publication_id is not null and v_head.expected_ka_publication_id is not null, 'freshness tracks only runtime sales source heads');

  -- Internal exact LPU uses canonical quantity before aggregation. The 3 L split sale
  -- (154548 = 1/4 of 150021) and the 12 L main-code KA sale both resolve to 12 L
  -- per canonical 150021 unit. This value is calculation infrastructure, not a viewer surface.
  set local role postgres;
  select * into v_lpu
  from public.current_canonical_product_lpu('1237')
  where canonical_product_code='150021';
  perform pg_temp.assert_true(v_lpu.sellout_lpu_candidate=12, 'split-code Sellout must normalize to exact 12 L per canonical unit');
  perform pg_temp.assert_true(v_lpu.ka_lpu_candidate=12, 'main-code KA must resolve to exact 12 L per canonical unit');
  perform pg_temp.assert_true(v_lpu.active_lpu=12 and v_lpu.active_source='SELLOUT', 'Sellout remains canonical LPU priority when both sources agree');
  perform pg_temp.assert_true(public.canonical_product_lpu('1237','154548')=12, 'split code must resolve the same canonical 12 L LPU');
  set local role authenticated;
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',v_admin::text,true);

  select * into v_fresh from public.read_current_product_domain_freshness() where scope_key='1237';
  perform pg_temp.assert_true(v_fresh.freshness_state='FRESH' and v_fresh.is_fresh, 'viewer-safe readiness reports FRESH');

  -- Viewer can read readiness but cannot mutate/reconcile.
  perform set_config('request.jwt.claim.sub',v_viewer::text,true);
  begin
    perform public.reconcile_product_domain_freshness('1237');
  exception when insufficient_privilege then
    v_viewer_rejected := true;
  end;
  perform pg_temp.assert_true(v_viewer_rejected, 'viewer cannot reconcile product normalization freshness');
  select * into v_fresh from public.read_current_product_domain_freshness() where scope_key='1237';
  perform pg_temp.assert_true(v_fresh.freshness_state='FRESH' and v_fresh.freshness_error is null, 'viewer readiness is sanitized and business-safe');
end;
$$;

rollback;
