\set ON_ERROR_STOP on
begin;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if not condition then raise exception 'ASSERTION FAILED: %', message; end if; end $$;

create or replace function pg_temp.create_publish_fixture(
  p_user_id uuid,
  p_contract_id uuid,
  p_source_kind text,
  p_scope_key text,
  p_rows jsonb,
  p_hash_char text,
  p_headers jsonb default null
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
  v_headers jsonb;
begin
  select coalesce(p_headers,required_headers) into v_headers
  from public.source_contract_versions where id=p_contract_id;

  insert into public.import_batches(
    id,source_contract_version_id,source_kind,scope_key,source_sheet,source_headers,
    storage_object_path,declared_file_hash,verified_file_hash,file_size_bytes,
    expected_rows,expected_chunks,received_chunks,staged_rows,expected_control_totals,
    status,source_verified_at,created_by
  )
  select v_batch,p_contract_id,p_source_kind,p_scope_key,sc.required_sheet,v_headers,
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
  values(v_candidate,v_batch,v_validation,v_reconciliation,jsonb_build_object('fixture',true),'READY',p_user_id);
  select active_publication_id into v_expected_head from public.publication_heads where source_kind=p_source_kind and scope_key=p_scope_key;
  v_publication := public.publish_candidate(v_candidate,v_expected_head);
  return v_publication;
end;
$$;

do $$
declare
  v_admin uuid := gen_random_uuid();
  v_viewer uuid := gen_random_uuid();
  v_ka_contract uuid;
  v_stock_contract uuid;
  v_row record;
  v_summary record;
  v_result record;
  v_count integer;
  v_failed boolean;
begin
  insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values
    (v_admin,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','p03au-admin@example.test','x',now(),'{}','{}',now(),now()),
    (v_viewer,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','p03au-viewer@example.test','x',now(),'{}','{}',now(),now());
  update public.user_profiles set role='admin' where user_id=v_admin;
  update public.user_profiles set role='viewer' where user_id=v_viewer;

  select id into v_ka_contract from public.source_contract_versions where source_kind='KA_DELIVERY' and version='1' and is_active;
  select id into v_stock_contract from public.source_contract_versions where source_kind='WAREHOUSE_STOCK' and version='1' and is_active;
  perform pg_temp.assert_true(v_ka_contract is not null, 'KA_DELIVERY v1 must be active');
  perform pg_temp.assert_true(v_stock_contract is not null, 'WAREHOUSE_STOCK v1 must be active');

  set local role authenticated;
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',v_admin::text,true);

  -- Authoritative source evidence gives canonical 150021 an LPU of 12.
  perform pg_temp.create_publish_fixture(
    v_admin,v_ka_contract,'KA_DELIVERY','1237',
    jsonb_build_array(
      jsonb_build_object('Bayi/Dist Kodu','1237','Ürün Kodu','150021','Malzeme kısa metni','EFES MAIN','Litre','12','Miktar','1','Yükleme Tarihi','2026-08-14')
    ),'a'
  );

  -- First snapshot has one resolved product and one unresolved product.
  perform pg_temp.create_publish_fixture(
    v_admin,v_stock_contract,'WAREHOUSE_STOCK','1237',
    jsonb_build_array(
      jsonb_build_object('Malzeme numarası','150021','Malzeme tanımı','EFES MAIN','Tahditsiz kullanılabilir','10'),
      jsonb_build_object('Malzeme numarası','3046','Malzeme tanımı','CO2','Tahditsiz kullanılabilir','5')
    ),'b'
  );

  select * into v_row from public.read_current_warehouse_stock_ui() where scope_key='1237' and product_code='150021';
  perform pg_temp.assert_true(v_row.lpu=12 and v_row.available_litres=120 and v_row.litre_resolution_state='RESOLVED', 'source LPU remains viewer-safe and exact');

  select * into v_row from public.read_current_warehouse_stock_ui() where scope_key='1237' and product_code='3046';
  perform pg_temp.assert_true(v_row.lpu is null and v_row.available_litres is null and v_row.litre_resolution_state='PARTIAL', 'missing LPU stays NULL/PARTIAL, never zero');

  select * into v_summary from public.read_current_warehouse_stock_ui_summary() where scope_key='1237';
  perform pg_temp.assert_true(v_summary.business_row_count=2, 'summary keeps canonical business row count');
  perform pg_temp.assert_true(v_summary.total_available_litres is null and v_summary.total_litres_state='PARTIAL', 'official total litres must remain null while any non-zero stock row lacks LPU');
  perform pg_temp.assert_true(v_summary.litre_resolved_count=1 and v_summary.litre_partial_count=1, 'summary exposes explicit litre resolution counts');

  -- Admin can persist a missing LPU. The UI total then becomes authoritative and fully resolved.
  select * into v_result from public.set_warehouse_stock_lpu_overrides(
    '1237',jsonb_build_array(jsonb_build_object('product_code','3046','lpu',2)),false
  );
  perform pg_temp.assert_true(v_result.updated_count=1 and v_result.remaining_missing_count=0, 'admin LPU save updates exactly one product and clears missing state');

  select * into v_row from public.read_current_warehouse_stock_ui() where scope_key='1237' and product_code='3046';
  perform pg_temp.assert_true(v_row.lpu=2 and v_row.available_litres=10 and v_row.litre_resolution_state='RESOLVED', 'manual approved LPU becomes effective for the current row');
  select * into v_summary from public.read_current_warehouse_stock_ui_summary() where scope_key='1237';
  perform pg_temp.assert_true(v_summary.total_available_litres=130 and v_summary.total_litres_state='RESOLVED', 'official total litres comes from the backend after all non-zero rows resolve');

  select count(*) into v_count from public.warehouse_stock_lpu_override_audit where scope_key='1237' and canonical_product_code='3046' and old_effective_lpu is null and new_lpu=2 and changed_by=v_admin;
  perform pg_temp.assert_true(v_count=1, 'first manual LPU definition is audited without exposing audit in the read RPC');

  -- A later FULL_REPLACE stock publication changes quantities but does not delete the product master override.
  perform pg_temp.create_publish_fixture(
    v_admin,v_stock_contract,'WAREHOUSE_STOCK','1237',
    jsonb_build_array(
      jsonb_build_object('Malzeme numarası','150021','Malzeme tanımı','EFES MAIN','Tahditsiz kullanılabilir','1'),
      jsonb_build_object('Malzeme numarası','3046','Malzeme tanımı','CO2','Tahditsiz kullanılabilir','7')
    ),'c'
  );
  select * into v_row from public.read_current_warehouse_stock_ui() where scope_key='1237' and product_code='3046';
  perform pg_temp.assert_true(v_row.exact_available_quantity=7 and v_row.lpu=2 and v_row.available_litres=14, 'manual LPU persists across FULL_REPLACE warehouse stock publication');

  -- Existing effective LPU edits require server confirmation at >=25 percent variance.
  v_failed := false;
  begin
    perform public.set_warehouse_stock_lpu_overrides(
      '1237',jsonb_build_array(jsonb_build_object('product_code','150021','lpu',20)),false
    );
  exception when sqlstate '22023' then
    v_failed := position('LPU_CONFIRM_REQUIRED' in sqlerrm) > 0;
  end;
  perform pg_temp.assert_true(v_failed, '>=25 percent LPU edit must be rejected until explicitly confirmed');

  select * into v_result from public.set_warehouse_stock_lpu_overrides(
    '1237',jsonb_build_array(jsonb_build_object('product_code','150021','lpu',20)),true
  );
  perform pg_temp.assert_true(v_result.updated_count=1, 'confirmed large LPU edit succeeds');
  select count(*) into v_count from public.warehouse_stock_lpu_override_audit where scope_key='1237' and canonical_product_code='150021' and old_effective_lpu=12 and new_lpu=20 and changed_by=v_admin;
  perform pg_temp.assert_true(v_count=1, 'large change audit stores old effective and new approved LPU');

  -- Viewer reads the business surface but cannot see admin internals or mutate LPU master data.
  perform set_config('request.jwt.claim.sub',v_viewer::text,true);
  select count(*) into v_count from public.read_current_warehouse_stock_ui() where scope_key='1237';
  perform pg_temp.assert_true(v_count=2, 'viewer can read current warehouse stock UI rows');
  select count(*) into v_count from public.warehouse_stock_lpu_overrides;
  perform pg_temp.assert_true(v_count=0, 'viewer RLS hides LPU override internals');
  select count(*) into v_count from public.warehouse_stock_lpu_override_audit;
  perform pg_temp.assert_true(v_count=0, 'viewer RLS hides LPU audit internals');

  v_failed := false;
  begin
    perform public.set_warehouse_stock_lpu_overrides(
      '1237',jsonb_build_array(jsonb_build_object('product_code','3046','lpu',3)),true
    );
  exception when others then
    v_failed := true;
  end;
  perform pg_temp.assert_true(v_failed, 'viewer cannot mutate Litre / Birim master data');
end;
$$;

rollback;
