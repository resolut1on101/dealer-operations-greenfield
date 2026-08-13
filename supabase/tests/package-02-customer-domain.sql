\set ON_ERROR_STOP on
begin;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if not condition then raise exception 'ASSERTION FAILED: %', message; end if; end $$;

do $$
declare
  v_admin_id uuid := gen_random_uuid(); v_viewer_id uuid := gen_random_uuid(); v_contract_id uuid; v_v2_contract_id uuid; v_v3_contract_id uuid;
  v_batch_id uuid := gen_random_uuid(); v_batch_two_id uuid := gen_random_uuid(); v_failed_v3_batch_id uuid := gen_random_uuid(); v_semantic_batch_id uuid := gen_random_uuid(); v_semantic_chunk_id uuid := gen_random_uuid(); v_semantic_validation_id uuid;
  v_validation_id uuid := gen_random_uuid(); v_reconciliation_id uuid := gen_random_uuid(); v_candidate_id uuid := gen_random_uuid(); v_publication_id uuid := gen_random_uuid();
  v_validation_two_id uuid := gen_random_uuid(); v_reconciliation_two_id uuid := gen_random_uuid(); v_candidate_two_id uuid := gen_random_uuid(); v_publication_two_id uuid := gen_random_uuid();
  v_bad_batch_id uuid := gen_random_uuid(); v_bad_validation_batch_id uuid := gen_random_uuid(); v_bad_reconciliation_batch_id uuid := gen_random_uuid();
  v_bad_reconciliation_id uuid := gen_random_uuid(); v_bad_validation_candidate_id uuid := gen_random_uuid(); v_bad_validation_publication_id uuid := gen_random_uuid();
  v_bad_reconciliation_validation_id uuid := gen_random_uuid(); v_bad_reconciliation_candidate_id uuid := gen_random_uuid(); v_bad_reconciliation_publication_id uuid := gen_random_uuid();
  v_chunk_id uuid := gen_random_uuid(); v_chunk_two_id uuid := gen_random_uuid();
  v_snapshot_id uuid; v_snapshot_two_id uuid; v_result jsonb; v_rejected boolean := false; v_before bigint; v_after bigint;
begin
  insert into auth.users(id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values (v_admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p02-source-admin@example.test', 'x', now(), '{}', '{}', now(), now()),
         (v_viewer_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'p02-source-viewer@example.test', 'x', now(), '{}', '{}', now(), now());
  update public.user_profiles set role='admin' where user_id=v_admin_id;
  perform pg_temp.assert_true(
    (select count(*) = 2
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname in ('customer_master_snapshots', 'customer_master_observations')
       and c.relrowsecurity)
    and (select count(*) = 2
         from pg_policy p
         join pg_class c on c.oid = p.polrelid
         join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public'
           and c.relname in ('customer_master_snapshots', 'customer_master_observations')
           and p.polcmd = 'r'
           and p.polname in ('customer_master_snapshots_admin_read', 'customer_master_observations_admin_read')
           and 'authenticated'::regrole::oid = any(p.polroles)
           and pg_get_expr(p.polqual, p.polrelid) like '%is_admin()%')
    and has_table_privilege('authenticated', 'public.customer_master_snapshots', 'select')
    and has_table_privilege('authenticated', 'public.customer_master_observations', 'select')
    and not exists (
      select 1
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname in ('customer_master_snapshots', 'customer_master_observations')
        and p.polcmd = 'r'
        and pg_get_expr(p.polqual, p.polrelid) in ('true', '(true)')
    ),
    'Package 02 provenance tables use admin-only SELECT RLS with no permissive true policy'
  );
  perform pg_temp.assert_true(
    (select count(*) = 4
     from pg_class c
     join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public'
       and c.relname in ('customer_representatives', 'customer_representative_ssm_resolutions', 'customer_resolutions', 'customers')
       and c.relrowsecurity)
    and (select count(*) = 4
         from pg_policy p
         join pg_class c on c.oid = p.polrelid
         join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'public'
           and (c.relname, p.polname) in (
             ('customer_representatives', 'customer_representatives_admin_read'),
             ('customer_representative_ssm_resolutions', 'customer_representative_ssm_resolutions_admin_read'),
             ('customer_resolutions', 'customer_resolutions_admin_read'),
             ('customers', 'customers_admin_read')
           )
           and p.polcmd = 'r'
           and 'authenticated'::regrole::oid = any(p.polroles)
           and pg_get_expr(p.polqual, p.polrelid) like '%is_admin()%')
    and not exists (
      select 1
      from pg_policy p
      join pg_class c on c.oid = p.polrelid
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname = 'public'
        and c.relname in ('customer_representatives', 'customer_representative_ssm_resolutions', 'customer_resolutions', 'customers')
        and p.polcmd = 'r'
        and pg_get_expr(p.polqual, p.polrelid) in ('true', '(true)')
    ),
    'Package 02 technical and customer base tables use admin-only SELECT RLS with no permissive true policy'
  );
  set local role authenticated; set local request.jwt.claim.role='authenticated'; perform set_config('request.jwt.claim.sub', v_admin_id::text, true);
  select id into v_v2_contract_id from public.source_contract_versions where source_kind='CUSTOMER_MASTER' and version='2';
  perform pg_temp.assert_true(
    v_v2_contract_id is not null and exists (
      select 1 from public.source_contract_versions
      where id=v_v2_contract_id
        and source_kind='CUSTOMER_MASTER'
        and version='2'
        and required_sheet='Müşteri'
        and required_headers='["Müşteri","Müşteri Adı","Tabela Adı","Satış Temsilcisi Adı","Dist Satış Şefi Adı","Satış Kanalı Tanımı","Müşteri Hacim Segmenti","Müşteri Durumu"]'::jsonb
        and required_fields='["Müşteri","Müşteri Adı","Tabela Adı","Satış Temsilcisi Adı","Dist Satış Şefi Adı","Satış Kanalı Tanımı","Müşteri Hacim Segmenti","Müşteri Durumu"]'::jsonb
        and control_total_fields='{}'::jsonb
        and control_total_scales='{}'::jsonb
        and publication_mode='FULL_REPLACE'::public.publication_mode
        and not is_active
        and retired_at is not null
    ),
    'known-invalid CUSTOMER_MASTER version 2 is retired'
  );
  perform pg_temp.assert_true(
    not exists (select 1 from public.import_batches where source_contract_version_id=v_v2_contract_id),
    'retired CUSTOMER_MASTER version 2 has no import batch references'
  );
  select id into v_v3_contract_id from public.source_contract_versions where source_kind='CUSTOMER_MASTER' and version='3';
  perform pg_temp.assert_true(
    v_v3_contract_id is not null and exists (select 1 from public.source_contract_versions where id=v_v3_contract_id and not is_active and retired_at is not null),
    'known CUSTOMER_MASTER version 3 is retained and retired'
  );
  reset role;
  insert into public.import_batches(id,source_contract_version_id,source_kind,scope_key,source_sheet,source_headers,storage_object_path,declared_file_hash,file_size_bytes,expected_rows,expected_chunks,created_by,status)
  values (v_failed_v3_batch_id,v_v3_contract_id,'CUSTOMER_MASTER','historical-v3','SAPUI5 dışa aktarımı','[]','imports/'||v_failed_v3_batch_id||'/source.xlsx',repeat('f',64),1,0,0,v_admin_id,'FAILED');
  perform pg_temp.assert_true(
    exists (select 1 from public.import_batches where id=v_failed_v3_batch_id and source_contract_version_id=v_v3_contract_id and status='FAILED'),
    'retired CUSTOMER_MASTER version 3 may retain failed batch provenance'
  );
  select id into v_contract_id from public.source_contract_versions where source_kind='CUSTOMER_MASTER' and version='4';
  perform pg_temp.assert_true(
    v_contract_id is not null
    and (select count(*)=1 from public.source_contract_versions where source_kind='CUSTOMER_MASTER' and version='4')
    and exists (
      select 1 from public.source_contract_versions
      where id=v_contract_id
        and source_kind='CUSTOMER_MASTER'
        and version='4'
        and required_sheet='SAPUI5 dışa aktarımı'
        and required_headers='["Müşteri","Müşteri Adı","Tabela Adı","Satış Temsilcisi Adı","Dist Satış Şefi Adı","Satış Kanalı Tanımı","Müşteri Hacim Segmenti","Müşteri Durumu"]'::jsonb
        and required_fields='["Müşteri"]'::jsonb
        and control_total_fields='{}'::jsonb
        and control_total_scales='{}'::jsonb
        and publication_mode='FULL_REPLACE'::public.publication_mode
        and is_active
        and retired_at is null
        and created_by is null
    ),
    'migration-provided CUSTOMER_MASTER version 4 is canonical and active'
  );
  insert into public.import_batches(id,source_contract_version_id,source_kind,scope_key,source_sheet,source_headers,storage_object_path,declared_file_hash,file_size_bytes,expected_rows,expected_chunks,created_by,source_verified_at)
  values (v_semantic_batch_id,v_contract_id,'CUSTOMER_MASTER','semantic-validation','SAPUI5 dışa aktarımı','[]','imports/'||v_semantic_batch_id||'/source.xlsx',repeat('7',64),1,1,1,v_admin_id,now());
  insert into public.import_chunks(id,batch_id,chunk_no,row_offset,chunk_hash,server_chunk_hash,row_count) values (v_semantic_chunk_id,v_semantic_batch_id,0,0,repeat('8',64),repeat('8',64),1);
  insert into public.staging_rows(batch_id,chunk_id,source_row_no,payload,payload_hash,row_status)
  values (v_semantic_batch_id,v_semantic_chunk_id,1,jsonb_build_object('Müşteri','ABC-OUT-OF-SCOPE','Satış Temsilcisi Adı',null,'Müşteri Hacim Segmenti',null),repeat('9',64),'PENDING');
  update public.import_batches set received_chunks=1,staged_rows=1 where id=v_semantic_batch_id;
  set local role authenticated; v_semantic_validation_id := public.validate_import_batch(v_semantic_batch_id); reset role;
  perform pg_temp.assert_true(
    (select valid_rows=1 and blocked_rows=0 and duplicate_rows=0 from public.validation_runs where id=v_semantic_validation_id)
    and (select row_status='VALID' from public.staging_rows where batch_id=v_semantic_batch_id and source_row_no=1),
    'v4 allows non-500 rows with missing optional Package 02 fields to remain valid Package 01 rows'
  );
  reset role;
  insert into public.import_batches(id, source_contract_version_id, source_kind, scope_key, source_sheet, source_headers, storage_object_path, declared_file_hash, file_size_bytes, expected_rows, expected_chunks, created_by)
  values (v_batch_id, v_contract_id, 'CUSTOMER_MASTER', 'master', 'SAPUI5 dışa aktarımı', '[]', 'imports/'||v_batch_id||'/source.xlsx', repeat('a',64), 1, 1, 1, v_admin_id);
  set local role authenticated; begin perform public.create_customer_master_snapshot(v_batch_id, 'unpublished'); exception when others then v_rejected := true; end; reset role;
  perform pg_temp.assert_true(v_rejected, 'unpublished Package 01 batch cannot create a Package 02 snapshot');

  insert into public.validation_runs(id,batch_id,contract_version_id,valid_rows,status) values (v_validation_id,v_batch_id,v_contract_id,20,'PASSED');
  insert into public.import_reconciliations(id,batch_id,parsed_rows,valid_rows,excluded_rows,blocked_rows,duplicate_rows,expected_control_totals,actual_control_totals,status) values (v_reconciliation_id,v_batch_id,20,20,0,0,0,'{}','{}','MATCHED');
  insert into public.candidate_publications(id,batch_id,validation_run_id,reconciliation_id,manifest,created_by,status,published_at) values (v_candidate_id,v_batch_id,v_validation_id,v_reconciliation_id,'{}',v_admin_id,'PUBLISHED',now());
  insert into public.publications(id,candidate_id,source_kind,scope_key,version,manifest,published_by) values (v_publication_id,v_candidate_id,'CUSTOMER_MASTER','master',1,'{}',v_admin_id);
  update public.import_batches set source_verified_at='2026-08-01T10:00:00Z'::timestamptz,status='PUBLISHED',published_publication_id=v_publication_id,validation_run_id=v_validation_id,reconciliation_id=v_reconciliation_id where id=v_batch_id;

  update public.import_batches set source_verified_at=null where id=v_batch_id;
  v_rejected := false; set local role authenticated; begin perform public.create_customer_master_snapshot(v_batch_id, 'missing-source-verification'); exception when others then v_rejected := true; end; reset role;
  perform pg_temp.assert_true(v_rejected, 'missing source verification cannot create a Package 02 snapshot');
  update public.import_batches set source_verified_at='2026-08-01T10:00:00Z'::timestamptz where id=v_batch_id;

  insert into public.import_batches(id,source_contract_version_id,source_kind,scope_key,source_sheet,source_headers,storage_object_path,declared_file_hash,file_size_bytes,expected_rows,expected_chunks,created_by,source_verified_at,status,validation_run_id,reconciliation_id,published_publication_id)
  values (v_bad_batch_id,v_contract_id,'CUSTOMER_MASTER','master','SAPUI5 dışa aktarımı','[]','imports/'||v_bad_batch_id||'/source.xlsx',repeat('c',64),1,1,1,v_admin_id,now(),'PUBLISHED',v_validation_id,v_reconciliation_id,v_publication_id);
  v_rejected := false; set local role authenticated; begin perform public.create_customer_master_snapshot(v_bad_batch_id, 'wrong-candidate-batch'); exception when others then v_rejected := true; end; reset role;
  perform pg_temp.assert_true(v_rejected, 'candidate from another batch cannot create a Package 02 snapshot');

  insert into public.import_batches(id,source_contract_version_id,source_kind,scope_key,source_sheet,source_headers,storage_object_path,declared_file_hash,file_size_bytes,expected_rows,expected_chunks,created_by,source_verified_at,status)
  values (v_bad_validation_batch_id,v_contract_id,'CUSTOMER_MASTER','master','SAPUI5 dışa aktarımı','[]','imports/'||v_bad_validation_batch_id||'/source.xlsx',repeat('d',64),1,1,1,v_admin_id,now(),'PUBLISHED');
  insert into public.import_reconciliations(id,batch_id,parsed_rows,valid_rows,excluded_rows,blocked_rows,duplicate_rows,expected_control_totals,actual_control_totals,status) values (v_bad_reconciliation_id,v_bad_validation_batch_id,1,1,0,0,0,'{}','{}','MATCHED');
  insert into public.candidate_publications(id,batch_id,validation_run_id,reconciliation_id,manifest,created_by,status,published_at) values (v_bad_validation_candidate_id,v_bad_validation_batch_id,v_validation_id,v_bad_reconciliation_id,'{}',v_admin_id,'PUBLISHED',now());
  insert into public.publications(id,candidate_id,source_kind,scope_key,version,manifest,published_by) values (v_bad_validation_publication_id,v_bad_validation_candidate_id,'CUSTOMER_MASTER','master',3,'{}',v_admin_id);
  update public.import_batches set validation_run_id=v_validation_id,reconciliation_id=v_bad_reconciliation_id,published_publication_id=v_bad_validation_publication_id where id=v_bad_validation_batch_id;
  v_rejected := false; set local role authenticated; begin perform public.create_customer_master_snapshot(v_bad_validation_batch_id, 'wrong-validation-batch'); exception when others then v_rejected := true; end; reset role;
  perform pg_temp.assert_true(v_rejected, 'validation from another batch cannot create a Package 02 snapshot');

  insert into public.import_batches(id,source_contract_version_id,source_kind,scope_key,source_sheet,source_headers,storage_object_path,declared_file_hash,file_size_bytes,expected_rows,expected_chunks,created_by,source_verified_at,status)
  values (v_bad_reconciliation_batch_id,v_contract_id,'CUSTOMER_MASTER','master','SAPUI5 dışa aktarımı','[]','imports/'||v_bad_reconciliation_batch_id||'/source.xlsx',repeat('e',64),1,1,1,v_admin_id,now(),'PUBLISHED');
  insert into public.validation_runs(id,batch_id,contract_version_id,valid_rows,status) values (v_bad_reconciliation_validation_id,v_bad_reconciliation_batch_id,v_contract_id,1,'PASSED');
  insert into public.candidate_publications(id,batch_id,validation_run_id,reconciliation_id,manifest,created_by,status,published_at) values (v_bad_reconciliation_candidate_id,v_bad_reconciliation_batch_id,v_bad_reconciliation_validation_id,v_reconciliation_id,'{}',v_admin_id,'PUBLISHED',now());
  insert into public.publications(id,candidate_id,source_kind,scope_key,version,manifest,published_by) values (v_bad_reconciliation_publication_id,v_bad_reconciliation_candidate_id,'CUSTOMER_MASTER','master',4,'{}',v_admin_id);
  update public.import_batches set validation_run_id=v_bad_reconciliation_validation_id,reconciliation_id=v_reconciliation_id,published_publication_id=v_bad_reconciliation_publication_id where id=v_bad_reconciliation_batch_id;
  v_rejected := false; set local role authenticated; begin perform public.create_customer_master_snapshot(v_bad_reconciliation_batch_id, 'wrong-reconciliation-batch'); exception when others then v_rejected := true; end; reset role;
  perform pg_temp.assert_true(v_rejected, 'reconciliation from another batch cannot create a Package 02 snapshot');

  update public.publications set source_kind='OTHER_SOURCE' where id=v_publication_id;
  v_rejected := false; set local role authenticated; begin perform public.create_customer_master_snapshot(v_batch_id, 'wrong-publication-kind'); exception when others then v_rejected := true; end; reset role;
  perform pg_temp.assert_true(v_rejected, 'wrong publication source kind cannot create a Package 02 snapshot');
  update public.publications set source_kind='CUSTOMER_MASTER' where id=v_publication_id;
  update public.candidate_publications set status='READY' where id=v_candidate_id;
  v_rejected := false; set local role authenticated; begin perform public.create_customer_master_snapshot(v_batch_id, 'unpublished-candidate'); exception when others then v_rejected := true; end; reset role;
  perform pg_temp.assert_true(v_rejected, 'unpublished candidate cannot create a Package 02 snapshot');
  update public.candidate_publications set status='PUBLISHED' where id=v_candidate_id;

  insert into public.import_chunks(id,batch_id,chunk_no,row_offset,chunk_hash,server_chunk_hash,row_count) values (v_chunk_id,v_batch_id,0,0,repeat('1',64),repeat('1',64),40);
  with source_rows(source_row_no,payload,row_status) as (
    values
      (1,jsonb_build_object('Müşteri','500001','Müşteri Adı','Alpha','Tabela Adı','Alpha Shop','Satış Temsilcisi Adı','Rep Above','Dist Satış Şefi Adı','SSM A','Satış Kanalı Tanımı','Standart Açık','Müşteri Hacim Segmenti','A Diamond','Müşteri Durumu','Aktif'),'VALID'::public.staging_row_status),
      (2,jsonb_build_object('Müşteri','500001','Müşteri Adı','Alpha','Tabela Adı','Alpha Shop','Satış Temsilcisi Adı','Rep Above','Dist Satış Şefi Adı','SSM A','Satış Kanalı Tanımı','Standart Açık','Müşteri Hacim Segmenti','A Diamond','Müşteri Durumu','Pasif'),'VALID'::public.staging_row_status),
      (3,jsonb_build_object('Müşteri','500002','Müşteri Adı','Cancelled','Tabela Adı','Trade','Satış Temsilcisi Adı','Rep Exact','Dist Satış Şefi Adı','SSM A','Satış Kanalı Tanımı','Horeca','Müşteri Hacim Segmenti','Gold','Müşteri Durumu','İptal'),'VALID'::public.staging_row_status),
      (4,jsonb_build_object('Müşteri','500003','Müşteri Adı','Unknown','Tabela Adı','Trade','Satış Temsilcisi Adı','Rep Tie','Dist Satış Şefi Adı','SSM B','Satış Kanalı Tanımı','Otel','Müşteri Hacim Segmenti','Silver','Müşteri Durumu','Bilinmiyor'),'VALID'::public.staging_row_status),
      (5,jsonb_build_object('Müşteri','500004','Müşteri Adı','Passive','Tabela Adı','Trade','Satış Temsilcisi Adı','Rep Below','Dist Satış Şefi Adı','SSM C','Satış Kanalı Tanımı','Standart Kapalı','Müşteri Hacim Segmenti','Bronze','Müşteri Durumu','Pasif'),'VALID'::public.staging_row_status),
      (6,jsonb_build_object('Müşteri','500005','Müşteri Adı','Cancelled Unknown','Tabela Adı','Trade','Satış Temsilcisi Adı','Rep Zero','Satış Kanalı Tanımı','Ekomini','Müşteri Hacim Segmenti','Bronze','Müşteri Durumu','İptal'),'VALID'::public.staging_row_status),
      (7,jsonb_build_object('Müşteri','500006','Müşteri Adı','Conflict A','Tabela Adı','Trade A','Satış Temsilcisi Adı','Rep Conflict','Dist Satış Şefi Adı','SSM A','Satış Kanalı Tanımı','Standart Açık','Müşteri Hacim Segmenti','Gold','Müşteri Durumu','Aktif'),'VALID'::public.staging_row_status),
      (8,jsonb_build_object('Müşteri','500006','Müşteri Adı','Conflict B','Tabela Adı','Trade B','Satış Temsilcisi Adı','Rep Conflict','Dist Satış Şefi Adı','SSM B','Satış Kanalı Tanımı','Standart Kapalı','Müşteri Hacim Segmenti','Silver','Müşteri Durumu','Aktif'),'VALID'::public.staging_row_status),
      (9,jsonb_build_object('Müşteri','ABC500001','Müşteri Adı','Out of Scope','Müşteri Durumu','Aktif'),'VALID'::public.staging_row_status),
      (10,jsonb_build_object('Müşteri','500005','Müşteri Durumu','Bilinmiyor'),'VALID'::public.staging_row_status),
      (11,jsonb_build_object('Müşteri','500007','Müşteri Durumu','Aktif (A)'),'VALID'::public.staging_row_status),
      (12,jsonb_build_object('Müşteri','500008','Müşteri Durumu','Pasif (P)'),'VALID'::public.staging_row_status),
      (13,jsonb_build_object('Müşteri','500009','Müşteri Durumu','İPTAL'),'VALID'::public.staging_row_status),
      (14,jsonb_build_object('Müşteri','500010','Müşteri Durumu','iptal'),'VALID'::public.staging_row_status),
      (15,jsonb_build_object('Müşteri','500011','Müşteri Durumu','İptal (C)'),'VALID'::public.staging_row_status),
      (16,jsonb_build_object('Müşteri','500012','Müşteri Durumu','cancelled'),'VALID'::public.staging_row_status),
      (17,jsonb_build_object('Müşteri','500013','Müşteri Durumu','canceled'),'VALID'::public.staging_row_status),
      (9001,jsonb_build_object('Müşteri','500701','Müşteri Adı','Blocked','Müşteri Durumu','Aktif'),'BLOCKED'::public.staging_row_status),
      (9002,jsonb_build_object('Müşteri','500702','Müşteri Adı','Excluded','Müşteri Durumu','Aktif'),'EXCLUDED'::public.staging_row_status),
      (9003,jsonb_build_object('Müşteri','500703','Müşteri Adı','Duplicate','Müşteri Durumu','Aktif'),'DUPLICATE'::public.staging_row_status)
  )
  insert into public.staging_rows(batch_id,chunk_id,source_row_no,payload,payload_hash,row_status)
  select v_batch_id,v_chunk_id,source_row_no,payload,encode(digest(payload::text,'sha256'),'hex'),row_status from source_rows;
  insert into public.staging_rows(batch_id,chunk_id,source_row_no,payload,payload_hash,row_status)
  select v_batch_id,v_chunk_id,1000+g,jsonb_build_object('Müşteri','50010'||g,'Satış Temsilcisi Adı','Rep Above','Dist Satış Şefi Adı','SSM A','Satış Kanalı Tanımı','Standart Açık','Müşteri Durumu','Aktif'),encode(digest(jsonb_build_object('Müşteri','50010'||g,'Satış Temsilcisi Adı','Rep Above','Dist Satış Şefi Adı','SSM A','Satış Kanalı Tanımı','Standart Açık','Müşteri Durumu','Aktif')::text,'sha256'),'hex'),'VALID'::public.staging_row_status from generate_series(1,9) g
  union all select v_batch_id,v_chunk_id,1100,jsonb_build_object('Müşteri','5001099','Satış Temsilcisi Adı','Rep Above','Dist Satış Şefi Adı','SSM B','Satış Kanalı Tanımı','Standart Açık','Müşteri Durumu','Aktif'),encode(digest(jsonb_build_object('Müşteri','5001099','Satış Temsilcisi Adı','Rep Above','Dist Satış Şefi Adı','SSM B','Satış Kanalı Tanımı','Standart Açık','Müşteri Durumu','Aktif')::text,'sha256'),'hex'),'VALID'::public.staging_row_status;
  insert into public.staging_rows(batch_id,chunk_id,source_row_no,payload,payload_hash,row_status)
  select v_batch_id,v_chunk_id,2000+g,jsonb_build_object('Müşteri','50020'||g,'Satış Temsilcisi Adı','Rep Exact','Dist Satış Şefi Adı','SSM A','Satış Kanalı Tanımı','Horeca','Müşteri Durumu','Aktif'),encode(digest(jsonb_build_object('Müşteri','50020'||g,'Satış Temsilcisi Adı','Rep Exact','Dist Satış Şefi Adı','SSM A','Satış Kanalı Tanımı','Horeca','Müşteri Durumu','Aktif')::text,'sha256'),'hex'),'VALID'::public.staging_row_status from generate_series(1,9) g
  union all select v_batch_id,v_chunk_id,2100,jsonb_build_object('Müşteri','5002099','Satış Temsilcisi Adı','Rep Exact','Dist Satış Şefi Adı','SSM B','Satış Kanalı Tanımı','Horeca','Müşteri Durumu','Aktif'),encode(digest(jsonb_build_object('Müşteri','5002099','Satış Temsilcisi Adı','Rep Exact','Dist Satış Şefi Adı','SSM B','Satış Kanalı Tanımı','Horeca','Müşteri Durumu','Aktif')::text,'sha256'),'hex'),'VALID'::public.staging_row_status;
  insert into public.staging_rows(batch_id,chunk_id,source_row_no,payload,payload_hash,row_status)
  values
    (v_batch_id,v_chunk_id,2351,jsonb_build_object('Müşteri','500201','Satış Temsilcisi Adı',null,'Dist Satış Şefi Adı','SSM A','Satış Kanalı Tanımı','Horeca','Müşteri Durumu','Aktif'),encode(digest(jsonb_build_object('Müşteri','500201','Satış Temsilcisi Adı',null,'Dist Satış Şefi Adı','SSM A','Satış Kanalı Tanımı','Horeca','Müşteri Durumu','Aktif')::text,'sha256'),'hex'),'VALID'),
    (v_batch_id,v_chunk_id,2352,jsonb_build_object('Müşteri','500299','Satış Temsilcisi Adı','Rep Exact','Dist Satış Şefi Adı','SSM POISON','Satış Kanalı Tanımı','Horeca','Müşteri Durumu','Aktif'),encode(digest(jsonb_build_object('Müşteri','500299','Satış Temsilcisi Adı','Rep Exact','Dist Satış Şefi Adı','SSM POISON','Satış Kanalı Tanımı','Horeca','Müşteri Durumu','Aktif')::text,'sha256'),'hex'),'VALID'),
    (v_batch_id,v_chunk_id,2353,jsonb_build_object('Müşteri','500299','Satış Temsilcisi Adı','Rep Other','Dist Satış Şefi Adı','SSM POISON','Satış Kanalı Tanımı','Horeca','Müşteri Durumu','Aktif'),encode(digest(jsonb_build_object('Müşteri','500299','Satış Temsilcisi Adı','Rep Other','Dist Satış Şefi Adı','SSM POISON','Satış Kanalı Tanımı','Horeca','Müşteri Durumu','Aktif')::text,'sha256'),'hex'),'VALID');
  insert into public.staging_rows(batch_id,chunk_id,source_row_no,payload,payload_hash,row_status)
  select v_batch_id,v_chunk_id,3000+g,jsonb_build_object('Müşteri','50030'||g,'Satış Temsilcisi Adı','Rep Below','Dist Satış Şefi Adı',case when g<=6 then 'SSM A' else 'SSM B' end,'Satış Kanalı Tanımı','Otel','Müşteri Durumu','Aktif'),encode(digest(jsonb_build_object('Müşteri','50030'||g,'Satış Temsilcisi Adı','Rep Below','Dist Satış Şefi Adı',case when g<=6 then 'SSM A' else 'SSM B' end,'Satış Kanalı Tanımı','Otel','Müşteri Durumu','Aktif')::text,'sha256'),'hex'),'VALID'::public.staging_row_status from generate_series(1,10) g;
  insert into public.staging_rows(batch_id,chunk_id,source_row_no,payload,payload_hash,row_status)
  select v_batch_id,v_chunk_id,4000+g,jsonb_build_object('Müşteri','50040'||g,'Satış Temsilcisi Adı','Rep Tie','Dist Satış Şefi Adı',case when g<=5 then 'SSM A' else 'SSM B' end,'Satış Kanalı Tanımı','Ekomini','Müşteri Durumu','Aktif'),encode(digest(jsonb_build_object('Müşteri','50040'||g,'Satış Temsilcisi Adı','Rep Tie','Dist Satış Şefi Adı',case when g<=5 then 'SSM A' else 'SSM B' end,'Satış Kanalı Tanımı','Ekomini','Müşteri Durumu','Aktif')::text,'sha256'),'hex'),'VALID'::public.staging_row_status from generate_series(1,10) g;

  v_rejected := false; set local role authenticated; begin perform public.create_customer_master_snapshot(v_batch_id, 'arbitrary-cutoff', true, '2020-01-01T00:00:00Z'::timestamptz); exception when others then v_rejected := true; end; reset role;
  perform pg_temp.assert_true(v_rejected, 'caller cannot inject an arbitrary snapshot cutoff timestamp');
  set local role authenticated; v_snapshot_id := public.create_customer_master_snapshot(v_batch_id, 'p02-1'); reset role;
  perform pg_temp.assert_true((select as_of_at='2026-08-01T10:00:00Z'::timestamptz and as_of_source='UPLOAD_TIME_FALLBACK' from public.customer_master_snapshots where id=v_snapshot_id), 'snapshot A uses trusted upload-time fallback provenance');
  v_rejected := false; set local role authenticated; begin perform public.stage_customer_master_rows(v_snapshot_id, '[]'::jsonb); exception when others then v_rejected := true; end; reset role;
  perform pg_temp.assert_true(v_rejected, 'caller-supplied Package 02 row payload is not an accepted adapter input');
  set local role authenticated; perform public.stage_customer_master_rows(v_snapshot_id); reset role;
  select count(*) into v_before from public.customer_master_observations where snapshot_id=v_snapshot_id;
  set local role authenticated; perform public.stage_customer_master_rows(v_snapshot_id); reset role;
  select count(*) into v_after from public.customer_master_observations where snapshot_id=v_snapshot_id;
  perform pg_temp.assert_true(v_before=v_after, 'source-bound adapter retry is idempotent');
  perform pg_temp.assert_true(not exists (select 1 from public.customer_master_observations where snapshot_id=v_snapshot_id and customer_id in ('500701','500702','500703','ABC500001')), 'only VALID in-scope Package 01 rows enter Package 02');
  perform pg_temp.assert_true(exists (select 1 from public.staging_rows s where s.batch_id=v_batch_id and s.source_row_no=9 and s.row_status='VALID' and s.payload ->> 'Müşteri'='ABC500001'), 'out-of-scope source row remains in Package 01 staging');
  perform pg_temp.assert_true(
    exists (select 1 from public.customer_master_observations o join public.staging_rows s on s.id=o.source_staging_row_id where o.snapshot_id=v_snapshot_id and o.customer_id='500001')
    and not exists (select 1 from public.customer_master_observations o join public.staging_rows s on s.id=o.source_staging_row_id where o.snapshot_id=v_snapshot_id and o.customer_id='500001' and o.source_payload_hash is distinct from s.payload_hash),
    'Package 01 payload hash provenance is preserved'
  );

  set local role authenticated; perform public.resolve_customer_master_snapshot(v_snapshot_id); reset role;
  perform pg_temp.assert_true((select status='ACTIVE' and channel='OPEN' from public.customers where customer_id='500001'), 'active status precedence and Standart Açık mapping');
  perform pg_temp.assert_true((select customer_name='Alpha' and trade_name='Alpha Shop' and segment='A Diamond' from public.customers where customer_id='500001'), 'source-bound canonical profile resolution');
  perform pg_temp.assert_true((select status='CANCELLED' and channel='OPEN' from public.customers where customer_id='500002'), 'cancelled-only and Horeca mapping');
  perform pg_temp.assert_true((select status='ACTIVE' from public.customers where customer_id='500007'), 'Aktif (A) maps to ACTIVE');
  perform pg_temp.assert_true((select status='PASSIVE' from public.customers where customer_id='500008'), 'Pasif (P) maps to PASSIVE');
  perform pg_temp.assert_true((select status='CANCELLED' from public.customers where customer_id in ('500009','500010','500011','500012','500013') group by status having count(*)=5), 'all exact cancelled variants map to CANCELLED');
  perform pg_temp.assert_true((select channel='OPEN' from public.customers where customer_id='500003'), 'Otel maps to open channel');
  perform pg_temp.assert_true((select channel='CLOSED' from public.customers where customer_id='500004'), 'Standart Kapalı maps to closed channel');
  perform pg_temp.assert_true((select channel='CLOSED' and status='UNKNOWN' from public.customers where customer_id='500005'), 'Ekomini mapping and cancelled plus unknown status');
  perform pg_temp.assert_true((select channel='UNCLASSIFIED' from public.customers where customer_id='500006'), 'open/closed conflict is unclassified');
  perform pg_temp.assert_true((select status='UNKNOWN' and status_resolution_state='UNKNOWN_REVIEW' from public.customer_resolutions where customer_id='500003' and snapshot_id=v_snapshot_id), 'unrecognized status remains UNKNOWN review');
  perform pg_temp.assert_true((select channel_resolution_state='CHANNEL_CONFLICT' from public.customer_resolutions cr where cr.customer_id='500006' and cr.snapshot_id=v_snapshot_id), 'channel conflict state is retained');
  perform pg_temp.assert_true((select customer_name is null and customer_name_resolution_state='CONFLICT_REVIEW' and trade_name_resolution_state='CONFLICT_REVIEW' and segment_resolution_state='CONFLICT_REVIEW' from public.customer_resolutions cr where cr.customer_id='500006' and cr.snapshot_id=v_snapshot_id), 'profile conflicts are not arbitrarily selected');
  perform pg_temp.assert_true((select financial_scope_state='DEFERRED_PACKAGE_10' and not sellout_fkns_eligible from public.customer_resolutions cr where cr.customer_id='500002' and cr.snapshot_id=v_snapshot_id), 'financial scope is deferred');

  set local role authenticated;
  v_result := public.resolve_representative_ssm('Rep Above', v_snapshot_id); perform pg_temp.assert_true(v_result->>'state'='RESOLVED' and v_result->>'canonical_ssm'='SSM A' and (v_result->>'known_active_count')::bigint=11 and (v_result->>'dominant_ratio')::numeric > .9, 'above 90 percent dominant ratio');
  perform pg_temp.assert_true(
    (select count(*) = 11 from public.customers c join public.customer_resolutions cr on cr.customer_id=c.customer_id and cr.snapshot_id=c.active_snapshot_id join public.customer_representatives r on r.id=cr.representative_id where c.active_snapshot_id=v_snapshot_id and r.normalized_name='rep above' and c.canonical_ssm='SSM A' and c.ssm_resolution_state='RESOLVED')
    and (select count(*) = 0 from public.customers c join public.customer_resolutions cr on cr.customer_id=c.customer_id and cr.snapshot_id=c.active_snapshot_id join public.customer_representatives r on r.id=cr.representative_id where c.active_snapshot_id=v_snapshot_id and r.normalized_name='rep below' and (c.canonical_ssm is not null or c.ssm_resolution_state <> 'UNRESOLVED')),
    'resolving Representative A updates all and only its resolved current customers'
  );
  perform pg_temp.assert_true(
    (select canonical_ssm is null and ssm_resolution_state='UNRESOLVED' from public.customers where customer_id='500006'),
    'resolving a representative does not mutate a conflicting representative identity'
  );
  reset role;
  update public.customer_resolutions
  set status='PASSIVE', ssm_resolution_state='UNRESOLVED'
  where snapshot_id=v_snapshot_id and customer_id='500001';
  update public.customers
  set status='PASSIVE', canonical_ssm=null, ssm_resolution_state='UNRESOLVED'
  where customer_id='500001';
  set local role authenticated;
  v_result := public.resolve_representative_ssm('Rep Above', v_snapshot_id);
  perform pg_temp.assert_true(
    (v_result->>'state'='RESOLVED' and (v_result->>'known_active_count')::bigint=10)
    and (select count(*)=10 from public.customers c join public.customer_resolutions cr on cr.customer_id=c.customer_id and cr.snapshot_id=c.active_snapshot_id where c.active_snapshot_id=v_snapshot_id and cr.representative_id=(select id from public.customer_representatives where normalized_name='rep above') and cr.status='ACTIVE' and c.canonical_ssm='SSM A')
    and (select canonical_ssm is null from public.customers where customer_id='500001'),
    'inactive same-representative customer is excluded from SSM materialization'
  );
  reset role;
  update public.customer_resolutions
  set status='ACTIVE', ssm_resolution_state='UNRESOLVED'
  where snapshot_id=v_snapshot_id and customer_id='500001';
  update public.customers
  set status='ACTIVE', canonical_ssm=null, ssm_resolution_state='UNRESOLVED'
  where customer_id='500001';
  set local role authenticated;
  v_result := public.resolve_representative_ssm('Rep Above', v_snapshot_id);
  v_result := public.resolve_representative_ssm('Rep Below', v_snapshot_id); perform pg_temp.assert_true(v_result->>'state'='MANUAL_REVIEW' and (v_result->>'dominant_ratio')::numeric < .9, 'below 90 percent requires review');
  perform pg_temp.assert_true(
    (select count(*) = 11 from public.customers c join public.customer_resolutions cr on cr.customer_id=c.customer_id and cr.snapshot_id=c.active_snapshot_id join public.customer_representatives r on r.id=cr.representative_id where c.active_snapshot_id=v_snapshot_id and r.normalized_name='rep above' and c.canonical_ssm='SSM A' and c.ssm_resolution_state='RESOLVED')
    and (select count(*) = 11 from public.customers c join public.customer_resolutions cr on cr.customer_id=c.customer_id and cr.snapshot_id=c.active_snapshot_id join public.customer_representatives r on r.id=cr.representative_id where c.active_snapshot_id=v_snapshot_id and r.normalized_name='rep below' and c.canonical_ssm is null and c.ssm_resolution_state='MANUAL_REVIEW'),
    'Representative B review state does not overwrite Representative A customers'
  );
  v_result := public.resolve_representative_ssm('Rep Exact', v_snapshot_id); perform pg_temp.assert_true(v_result->>'state'='RESOLVED' and v_result->>'canonical_ssm'='SSM A' and (v_result->>'known_active_count')::bigint=10 and (v_result->>'dominant_ratio')::numeric = .9, 'exactly 90 percent dominant ratio');
  perform pg_temp.assert_true(
    (select representative_resolution_state='CONFLICTING' from public.customer_resolutions where snapshot_id=v_snapshot_id and customer_id='500299')
    and not exists (select 1 from public.customer_representative_ssm_resolutions rs join public.customer_representatives r on r.id=rs.representative_id where rs.snapshot_id=v_snapshot_id and r.normalized_name='rep exact' and rs.raw_ssm_names ? 'SSM POISON')
    and not exists (select 1 from public.customers where customer_id='500299' and canonical_ssm is not null),
    'conflicting raw representative poison is excluded from authoritative SSM evidence and customer materialization'
  );
  v_result := public.resolve_representative_ssm('Rep Tie', v_snapshot_id); perform pg_temp.assert_true(v_result->>'state'='MANUAL_REVIEW', 'tie requires review');
  v_result := public.resolve_representative_ssm('Rep Zero', v_snapshot_id); perform pg_temp.assert_true(v_result->>'state'='UNRESOLVED', 'zero denominator remains unresolved');
  perform pg_temp.assert_true(
    (select count(*) = 11 from public.customers c join public.customer_resolutions cr on cr.customer_id=c.customer_id and cr.snapshot_id=c.active_snapshot_id join public.customer_representatives r on r.id=cr.representative_id where c.active_snapshot_id=v_snapshot_id and r.normalized_name='rep above' and c.canonical_ssm='SSM A' and c.ssm_resolution_state='RESOLVED')
    and (select count(*) = 11 from public.customers c join public.customer_resolutions cr on cr.customer_id=c.customer_id and cr.snapshot_id=c.active_snapshot_id join public.customer_representatives r on r.id=cr.representative_id where c.active_snapshot_id=v_snapshot_id and r.normalized_name='rep below' and c.canonical_ssm is null and c.ssm_resolution_state='MANUAL_REVIEW'),
    'unresolved representative does not wipe unrelated customer hierarchy'
  );
  perform pg_temp.assert_true(
    not exists (
      select 1
      from public.customers c
      join public.customer_resolutions cr on cr.customer_id=c.customer_id and cr.snapshot_id=c.active_snapshot_id
      join public.customer_representatives r on r.id=cr.representative_id
      where c.active_snapshot_id=v_snapshot_id
        and c.canonical_ssm is not null
        and (cr.representative_resolution_state <> 'RESOLVED' or r.ssm_resolution_state <> 'RESOLVED' or r.canonical_ssm is distinct from c.canonical_ssm)
    ),
    'current customer chief values match their resolved representative SSM'
  );
  reset role;

  insert into public.import_batches(id,source_contract_version_id,source_kind,scope_key,source_sheet,source_headers,storage_object_path,declared_file_hash,file_size_bytes,expected_rows,expected_chunks,created_by,source_verified_at)
  values (v_batch_two_id,v_contract_id,'CUSTOMER_MASTER','master','SAPUI5 dışa aktarımı','[]','imports/'||v_batch_two_id||'/source.xlsx',repeat('b',64),1,1,1,v_admin_id,'2026-08-02T10:00:00Z'::timestamptz);
  insert into public.validation_runs(id,batch_id,contract_version_id,valid_rows,status) values (v_validation_two_id,v_batch_two_id,v_contract_id,1,'PASSED');
  insert into public.import_reconciliations(id,batch_id,parsed_rows,valid_rows,excluded_rows,blocked_rows,duplicate_rows,expected_control_totals,actual_control_totals,status) values (v_reconciliation_two_id,v_batch_two_id,1,1,0,0,0,'{}','{}','MATCHED');
  insert into public.candidate_publications(id,batch_id,validation_run_id,reconciliation_id,manifest,created_by,status,published_at) values (v_candidate_two_id,v_batch_two_id,v_validation_two_id,v_reconciliation_two_id,'{}',v_admin_id,'PUBLISHED',now());
  insert into public.publications(id,candidate_id,source_kind,scope_key,version,manifest,published_by) values (v_publication_two_id,v_candidate_two_id,'CUSTOMER_MASTER','master',2,'{}',v_admin_id);
  update public.import_batches set status='PUBLISHED',published_publication_id=v_publication_two_id,validation_run_id=v_validation_two_id,reconciliation_id=v_reconciliation_two_id where id=v_batch_two_id;
  insert into public.import_chunks(id,batch_id,chunk_no,row_offset,chunk_hash,server_chunk_hash,row_count) values (v_chunk_two_id,v_batch_two_id,0,0,repeat('2',64),repeat('2',64),2);
  insert into public.staging_rows(batch_id,chunk_id,source_row_no,payload,payload_hash,row_status)
  values (v_batch_two_id,v_chunk_two_id,1,jsonb_build_object('Müşteri','500001','Müşteri Adı','Alpha New','Tabela Adı','Alpha New Trade','Satış Temsilcisi Adı','Rep Above','Dist Satış Şefi Adı','SSM B','Satış Kanalı Tanımı','Otel','Müşteri Hacim Segmenti','Platinum','Müşteri Durumu','Aktif'),encode(digest(jsonb_build_object('Müşteri','500001','Müşteri Adı','Alpha New','Tabela Adı','Alpha New Trade','Satış Temsilcisi Adı','Rep Above','Dist Satış Şefi Adı','SSM B','Satış Kanalı Tanımı','Otel','Müşteri Hacim Segmenti','Platinum','Müşteri Durumu','Aktif')::text,'sha256'),'hex'),'VALID');
  set local role authenticated; v_snapshot_two_id := public.create_customer_master_snapshot(v_batch_two_id, 'p02-2', true); reset role;
  perform pg_temp.assert_true((select as_of_at='2026-08-02T10:00:00Z'::timestamptz and as_of_source='UPLOAD_TIME_FALLBACK' from public.customer_master_snapshots where id=v_snapshot_two_id), 'snapshot B uses trusted upload-time fallback provenance');
  perform pg_temp.assert_true((select as_of_at=(select max(s2.as_of_at) from public.customer_master_snapshots s2) from public.customer_master_snapshots s where s.id=v_snapshot_two_id), 'snapshot B is current by server-derived evidence');
  set local role authenticated; perform public.stage_customer_master_rows(v_snapshot_two_id); reset role;
  set local role authenticated; perform public.stage_customer_master_rows(v_snapshot_two_id); reset role;
  insert into public.staging_rows(batch_id,chunk_id,source_row_no,payload,payload_hash,row_status)
  values (v_batch_two_id,v_chunk_two_id,2,jsonb_build_object('Müşteri','500777','Müşteri Adı','Wrong Batch','Müşteri Durumu','Aktif'),encode(digest(jsonb_build_object('Müşteri','500777','Müşteri Adı','Wrong Batch','Müşteri Durumu','Aktif')::text,'sha256'),'hex'),'VALID');
  set local role authenticated; perform public.stage_customer_master_rows(v_snapshot_id); reset role;
  perform pg_temp.assert_true(not exists (select 1 from public.customer_master_observations o where o.snapshot_id=v_snapshot_id and o.customer_id='500777'), 'snapshot cannot consume another batch source rows');
  set local role authenticated; perform public.resolve_customer_master_snapshot(v_snapshot_two_id); reset role;
  set local role authenticated; v_result := public.resolve_representative_ssm('Rep Above', v_snapshot_two_id); reset role;
  perform pg_temp.assert_true(v_result->>'state'='RESOLVED' and v_result->>'canonical_ssm'='SSM B', 'newer snapshot promotes current representative SSM');
  perform pg_temp.assert_true((select canonical_ssm='SSM B' and ssm_resolution_state='RESOLVED' from public.customers where customer_id='500001'), 'current customer hierarchy uses newer SSM');
  set local role authenticated; perform public.resolve_customer_master_snapshot(v_snapshot_id); reset role;
  set local role authenticated; v_result := public.resolve_representative_ssm('Rep Above', v_snapshot_id); reset role;
  perform pg_temp.assert_true((select canonical_ssm='SSM B' and ssm_resolution_state='RESOLVED' from public.customer_representatives cr where cr.normalized_name='rep above'), 'historical SSM re-resolution cannot roll back representative current state');
  perform pg_temp.assert_true((select canonical_ssm='SSM B' and ssm_resolution_state='RESOLVED' from public.customers where customer_id='500001'), 'historical SSM re-resolution cannot roll back customer hierarchy');
  perform pg_temp.assert_true(exists (select 1 from public.customer_representative_ssm_resolutions r join public.customer_representatives cr on cr.id=r.representative_id where cr.normalized_name='rep above' and r.snapshot_id=v_snapshot_id and r.canonical_ssm='SSM A' and r.resolution_state='RESOLVED'), 'historical SSM resolution remains auditable');
  perform pg_temp.assert_true((select customer_name='Alpha New' and active_snapshot_id=v_snapshot_two_id from public.customers where customer_id='500001'), 'older snapshot re-resolution cannot overwrite current canonical state');
  perform pg_temp.assert_true((select current_snapshot_state='NOT_PRESENT_IN_CURRENT_MASTER' from public.customers where customer_id='500002'), 'missing current customer remains distinct from status');
  perform pg_temp.assert_true(
    public.customer_business_display_name('ESRA ARİ Esra Ari') = 'Esra Ari'
    and public.customer_business_display_name('OSMAN ÖKTEN Osman Ökten') = 'Osman Ökten'
    and public.customer_business_display_name('HASAN AKIN Hasan Akın') = 'Hasan Akın'
    and public.customer_business_display_name('ÖZDEN ÖZTEKİN ORTAKLIĞI Özden Öztekin') = 'ÖZDEN ÖZTEKİN ORTAKLIĞI Özden Öztekin'
    and public.customer_business_display_name('FARUK NAZİF KILIÇ Faruk Nafiz Kılıç') = 'FARUK NAZİF KILIÇ Faruk Nafiz Kılıç',
    'business display name removes only repeated-half source names and preserves meaningful company/person strings'
  );

  reset role; set local role authenticated; set local request.jwt.claim.role='authenticated'; perform set_config('request.jwt.claim.sub', v_viewer_id::text, true);
  perform pg_temp.assert_true(
    (select count(*) = 0 from public.customer_master_snapshots where id in (v_snapshot_id, v_snapshot_two_id)),
    'viewer cannot directly read Customer Master snapshot provenance'
  );
  perform pg_temp.assert_true(
    (select count(*) = 0 from public.customer_master_observations where snapshot_id in (v_snapshot_id, v_snapshot_two_id)),
    'viewer cannot directly read Customer Master observation provenance'
  );
  perform pg_temp.assert_true(
    (select count(*) = 0 from public.customer_resolutions where customer_id = '500001')
    and (select count(*) = 0 from public.customer_representatives)
    and (select count(*) = 0 from public.customer_representative_ssm_resolutions)
    and (select count(*) = 0 from public.customers where customer_id = '500001'),
    'viewer cannot directly read Package 02 technical base tables'
  );
  perform pg_temp.assert_true(
    (select representative = 'Rep Above' and chief = 'SSM B'
     from public.read_current_customer_business_surface() where customer_id = '500001'),
    'viewer safe business surface returns resolved representative and chief values'
  );
  perform pg_temp.assert_true(
    not exists (
      select 1
      from public.read_current_customer_business_surface()
      where customer_id = '500006'
    )
    and not exists (
      select 1
      from public.read_current_customer_business_surface()
      where status <> 'ACTIVE' or representative is null or chief is null
    ),
    'viewer portfolio surface excludes inactive and unresolved organization candidates'
  );
  perform pg_temp.assert_true(
    (select count(*) = 8
     from public.read_current_customer_business_surface() s
     cross join lateral jsonb_object_keys(to_jsonb(s)) as key
     where s.customer_id = '500001')
    and not exists (
      select 1
      from public.read_current_customer_business_surface() s
      cross join lateral jsonb_object_keys(to_jsonb(s)) as key
      where key in ('snapshot_id', 'source_observation_ids', 'resolution_evidence', 'raw_payload', 'current_resolution')
    ),
    'safe business surface exposes only fixed business columns and no technical evidence fields'
  );
  v_rejected := false; begin perform public.stage_customer_master_rows(v_snapshot_two_id); exception when others then v_rejected := true; end;
  perform pg_temp.assert_true(v_rejected, 'viewer cannot mutate Customer Master');
  reset role; set local role authenticated; set local request.jwt.claim.role='authenticated'; perform set_config('request.jwt.claim.sub', v_admin_id::text, true);
  perform pg_temp.assert_true(
    (select count(*) = 2 from public.customer_master_snapshots where id in (v_snapshot_id, v_snapshot_two_id)),
    'admin can directly read Customer Master snapshot provenance'
  );
  perform pg_temp.assert_true(
    (select count(*) > 0 from public.customer_master_observations where snapshot_id in (v_snapshot_id, v_snapshot_two_id)),
    'admin can directly read Customer Master observation provenance'
  );
  perform pg_temp.assert_true(
    (select count(*) > 0 from public.customer_resolutions where customer_id = '500001')
    and (select count(*) > 0 from public.customer_representatives)
    and (select count(*) > 0 from public.customer_representative_ssm_resolutions)
    and (select count(*) > 0 from public.customers where customer_id = '500001'),
    'admin retains direct technical Package 02 evidence access'
  );
end $$;
select 'Package 02 source-bound customer domain tests PASS.' as result;
rollback;
