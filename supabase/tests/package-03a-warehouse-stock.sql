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
  v_sellout_contract uuid;
  v_ka_contract uuid;
  v_stock_contract uuid;
  v_row record;
  v_summary record;
  v_count integer;
  v_failed boolean;
begin
  insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values
    (v_admin,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','p03a-admin@example.test','x',now(),'{}','{}',now(),now()),
    (v_viewer,'00000000-0000-0000-0000-000000000000','authenticated','authenticated','p03a-viewer@example.test','x',now(),'{}','{}',now(),now());
  update public.user_profiles set role='admin' where user_id=v_admin;
  update public.user_profiles set role='viewer' where user_id=v_viewer;

  select id into v_sellout_contract from public.source_contract_versions where source_kind='SELLOUT' and version='1' and is_active;
  select id into v_ka_contract from public.source_contract_versions where source_kind='KA_DELIVERY' and version='1' and is_active;
  select id into v_stock_contract from public.source_contract_versions where source_kind='WAREHOUSE_STOCK' and version='1' and is_active;
  perform pg_temp.assert_true(v_stock_contract is not null, 'WAREHOUSE_STOCK v1 must be active');
  perform pg_temp.assert_true((select publication_mode='FULL_REPLACE' from public.source_contract_versions where id=v_stock_contract), 'warehouse stock must be FULL_REPLACE');
  perform pg_temp.assert_true((select required_headers='["Malzeme numarası","Malzeme tanımı","Tahditsiz kullanılabilir"]'::jsonb from public.source_contract_versions where id=v_stock_contract), 'warehouse stock exact three-column contract');

  set local role authenticated;
  perform set_config('request.jwt.claim.role','authenticated',true);
  perform set_config('request.jwt.claim.sub',v_admin::text,true);

  -- Seed current runtime litre evidence. Standard split 154548 => 1/4 of 150021,
  -- high-alcohol case 152236 => 6 singles of canonical 152327.
  perform pg_temp.create_publish_fixture(
    v_admin,v_sellout_contract,'SELLOUT','1237',
    jsonb_build_array(
      jsonb_build_object('Bayi/Distribütör','1237','Malzeme Kodu','154548','Malzeme Tnm.','Split Beer','Mal Grubu Tnm.','Efes Pilsen','Miktar','1','Litre','3','Faturalama Tarihi','2026-08-01'),
      jsonb_build_object('Bayi/Distribütör','1237','Malzeme Kodu','152236','Malzeme Tnm.','Monkey Case','Mal Grubu Tnm.','Distile','Miktar','1','Litre','4.2','Faturalama Tarihi','2026-08-01')
    ),'a'
  );
  perform pg_temp.create_publish_fixture(
    v_admin,v_ka_contract,'KA_DELIVERY','1237',
    jsonb_build_array(
      jsonb_build_object('Bayi/Dist Kodu','1237','Ürün Kodu','150021','Malzeme kısa metni','Main Beer','Litre','12','Miktar','1','Yükleme Tarihi','2026-08-01'),
      jsonb_build_object('Bayi/Dist Kodu','1237','Ürün Kodu','152327','Malzeme kısa metni','Monkey Single','Litre','0.7','Miktar','1','Yükleme Tarihi','2026-08-01')
    ),'b'
  );

  -- First current-stock publication: five raw rows become three business rows.
  perform pg_temp.create_publish_fixture(
    v_admin,v_stock_contract,'WAREHOUSE_STOCK','1237',
    jsonb_build_array(
      jsonb_build_object('Malzeme numarası','150021','Malzeme tanımı','EFES MAIN','Tahditsiz kullanılabilir','10'),
      jsonb_build_object('Malzeme numarası','154548','Malzeme tanımı','EFES SPLIT','Tahditsiz kullanılabilir','3'),
      jsonb_build_object('Malzeme numarası','152327','Malzeme tanımı','MONKEY SINGLE','Tahditsiz kullanılabilir','4'),
      jsonb_build_object('Malzeme numarası','152236','Malzeme tanımı','MONKEY CASE','Tahditsiz kullanılabilir','2'),
      jsonb_build_object('Malzeme numarası','3046','Malzeme tanımı','CO2','Tahditsiz kullanılabilir','5')
    ),'c'
  );

  select * into v_summary from public.read_current_warehouse_stock_summary() where scope_key='1237';
  perform pg_temp.assert_true(v_summary.business_row_count=3, 'five raw stock rows collapse to three normal business rows without exposing split counts');
  perform pg_temp.assert_true(v_summary.litre_resolved_count=2 and v_summary.litre_partial_count=1, 'missing litre evidence remains partial, never zero');

  select * into v_row from public.read_current_warehouse_stock() where scope_key='1237' and product_code='150021';
  perform pg_temp.assert_true(v_row.exact_available_quantity=10.75, 'standard split stock keeps exact 10.75 canonical quantity');
  perform pg_temp.assert_true(v_row.lpu=12 and v_row.available_litres=129, 'standard stock litres use exact quantity, not rounded display quantity');

  select * into v_row from public.read_current_warehouse_stock() where scope_key='1237' and product_code='152327';
  perform pg_temp.assert_true(v_row.exact_available_quantity=16, 'high-alcohol case stock reverses into single/retail canonical quantity');
  perform pg_temp.assert_true(v_row.lpu=0.7 and v_row.available_litres=11.2, 'high-alcohol stock litres use canonical single-unit LPU');

  select * into v_row from public.read_current_warehouse_stock() where scope_key='1237' and product_code='3046';
  perform pg_temp.assert_true(v_row.exact_available_quantity=5 and v_row.lpu is null and v_row.available_litres is null and v_row.litre_resolution_state='PARTIAL', 'identity stock with missing LPU is preserved as partial/null');
  perform pg_temp.assert_true(not exists(select 1 from public.read_current_warehouse_stock() where product_code in ('154548','152236')), 'split/case raw codes never become normal business rows');

  -- FULL_REPLACE: next snapshot contains only one raw row; prior current rows are not carried forward.
  perform pg_temp.create_publish_fixture(
    v_admin,v_stock_contract,'WAREHOUSE_STOCK','1237',
    jsonb_build_array(jsonb_build_object('Malzeme numarası','150021','Malzeme tanımı','EFES MAIN','Tahditsiz kullanılabilir','7')),'d'
  );
  select count(*) into v_count from public.read_current_warehouse_stock() where scope_key='1237';
  perform pg_temp.assert_true(v_count=1, 'new FULL_REPLACE snapshot does not fabricate carry-forward stock history');
  select * into v_row from public.read_current_warehouse_stock() where scope_key='1237' and product_code='150021';
  perform pg_temp.assert_true(v_row.exact_available_quantity=7, 'new snapshot replaces the prior current quantity exactly');

  -- Exact signature is enforced server-side as well as in source recognition.
  v_failed:=false;
  begin
    perform pg_temp.create_publish_fixture(
      v_admin,v_stock_contract,'WAREHOUSE_STOCK','1237',
      jsonb_build_array(jsonb_build_object('Malzeme numarası','150021','Malzeme tanımı','EFES MAIN','Tahditsiz kullanılabilir','1','Unexpected','x')),'e',
      '["Malzeme numarası","Malzeme tanımı","Tahditsiz kullanılabilir","Unexpected"]'::jsonb
    );
  exception when others then
    v_failed:=true;
  end;
  perform pg_temp.assert_true(v_failed, 'extra warehouse source columns are rejected before current materialization');

  -- Same raw material code twice is not auto-summed, whether equal or conflicting.
  v_failed:=false;
  begin
    perform pg_temp.create_publish_fixture(
      v_admin,v_stock_contract,'WAREHOUSE_STOCK','1237',
      jsonb_build_array(
        jsonb_build_object('Malzeme numarası','150021','Malzeme tanımı','EFES MAIN','Tahditsiz kullanılabilir','1'),
        jsonb_build_object('Malzeme numarası','150021','Malzeme tanımı','EFES MAIN','Tahditsiz kullanılabilir','2')
      ),'f'
    );
  exception when others then
    v_failed:=true;
  end;
  perform pg_temp.assert_true(v_failed, 'duplicate material codes are blocking and are never silently summed');

  -- Viewer sees only the business read surface; base transformation tables remain admin-only.
  perform set_config('request.jwt.claim.sub',v_viewer::text,true);
  select count(*) into v_count from public.warehouse_stock_raw_rows;
  perform pg_temp.assert_true(v_count=0, 'viewer cannot read raw warehouse transformation rows');
  select count(*) into v_count from public.warehouse_stock_canonical_rows;
  perform pg_temp.assert_true(v_count=0, 'viewer cannot read base canonical warehouse rows');
  select count(*) into v_count from public.read_current_warehouse_stock() where scope_key='1237';
  perform pg_temp.assert_true(v_count=1, 'viewer can read the current canonical warehouse business surface');
end;
$$;

rollback;
