-- Runs after `supabase db reset` on local synthetic data. It verifies the Package 01
-- migration, idempotent chunk staging, exact reconciliation and rollback-safe publishing.
begin;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is distinct from true then raise exception 'Assertion failed: %', message; end if;
end;
$$;

do $$
declare
  admin_id uuid := '30000000-0000-0000-0000-000000000001';
  viewer_id uuid := '30000000-0000-0000-0000-000000000002';
  contract_id uuid; batch_one uuid; batch_two uuid; batch_bad uuid;
  candidate_one uuid; candidate_two uuid; publication_one uuid; publication_two uuid;
  chunk_one uuid; retry_chunk uuid; validation_id uuid; reconciliation_id uuid; retry_reconciliation_id uuid; rejected boolean; storage_updates integer;
  first_chunk_hash text; second_chunk_hash text;
begin
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values
    (admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'package01-admin@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
    (viewer_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'package01-viewer@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

  update public.user_profiles set role = 'admin' where user_id = admin_id;

  perform pg_temp.assert_true(
    public.canonical_control_totals('{"amount":151185.58999999994}'::jsonb, '{"amount":2}'::jsonb) = '{"amount":151185.59}'::jsonb,
    'decimal control totals canonicalize to the contract scale'
  );
  perform pg_temp.assert_true(
    public.canonical_control_totals('{"amount":151185.58}'::jsonb, '{"amount":2}'::jsonb) <> '{"amount":151185.59}'::jsonb,
    'material decimal differences remain mismatched'
  );
  perform pg_temp.assert_true(
    public.canonical_control_totals('{"count":2}'::jsonb, '{"count":0}'::jsonb) <> '{"count":1}'::jsonb,
    'integer differences remain mismatched'
  );

  set local role service_role;
  set local request.jwt.claim.role = 'service_role';
  reset role;
  set local role authenticated;
  set local request.jwt.claim.role = 'authenticated';
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  contract_id := public.register_source_contract(
    'SYNTHETIC_IMPORT', '1', 'Data', '["id","amount"]'::jsonb, '["id","amount"]'::jsonb,
    '{"amount":"amount"}'::jsonb, '{"amount":2}'::jsonb, 'FULL_REPLACE'::public.publication_mode
  );
  batch_one := (public.create_import_batch(contract_id, '2026-08', 'Data', '["id","amount"]', repeat('a', 64), 123, 2, 2, '{"amount":15.7500000001}')).id;
  perform pg_temp.assert_true((select storage_object_path = 'imports/' || id::text || '/source.xlsx' from public.import_batches where id = batch_one), 'AUD-04 server generates the storage path from batch identity');
  insert into storage.objects (bucket_id, name, owner, owner_id, metadata)
  select storage_bucket, storage_object_path, admin_id, admin_id::text, '{}'::jsonb from public.import_batches where id = batch_one;
  rejected := false;
  begin
    update storage.objects set name = 'client-controlled/unbound.xlsx'
    where bucket_id = 'source-evidence' and name = (select storage_object_path from public.import_batches where id = batch_one);
  exception when insufficient_privilege then rejected := true;
  end;
  perform pg_temp.assert_true(rejected, 'AUD-04 bound source object cannot be renamed to an unbound client path');
  update storage.objects set metadata = '{"retry":true}'::jsonb
  where bucket_id = 'source-evidence' and name = (select storage_object_path from public.import_batches where id = batch_one);
  get diagnostics storage_updates = row_count;
  perform pg_temp.assert_true(storage_updates = 1, 'AUD-04 metadata update on the valid bound path remains allowed');

  reset role;
  set local role service_role;
  set local request.jwt.claim.role = 'service_role';
  perform public.verify_import_source_hash(batch_one, repeat('a', 64), 123);
  reset role;
  set local role authenticated;
  set local request.jwt.claim.role = 'authenticated';
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  first_chunk_hash := public.import_chunk_payload_hash('[{"id":"1","amount":"10.25"}]');
  rejected := false;
  begin perform public.stage_import_chunk(batch_one, 0, 0, repeat('b', 64), 1, '[{"id":"1","amount":"10.25"}]'); exception when data_exception then rejected := true; end;
  perform pg_temp.assert_true(rejected, 'AUD-03 client hash must match the server payload digest on the first submission');
  chunk_one := public.stage_import_chunk(batch_one, 0, 0, first_chunk_hash, 1, '[{"id":"1","amount":"10.25"}]');
  retry_chunk := public.stage_import_chunk(batch_one, 0, 0, first_chunk_hash, 1, '[{"id":"1","amount":"10.25"}]');
  perform pg_temp.assert_true(chunk_one = retry_chunk, 'identical chunk retry returns the original chunk');
  second_chunk_hash := public.import_chunk_payload_hash('[{"id":"2","amount":"5.50"}]');
  perform public.stage_import_chunk(batch_one, 1, 1, second_chunk_hash, 1, '[{"id":"2","amount":"5.50"}]');
  rejected := false;
  begin perform public.stage_import_chunk(batch_one, 1, 1, public.import_chunk_payload_hash('[{"id":"2","amount":"6.00"}]'), 1, '[{"id":"2","amount":"6.00"}]'); exception when unique_violation then rejected := true; end;
  perform pg_temp.assert_true(rejected, 'different content cannot reuse a chunk number');
  validation_id := public.validate_import_batch(batch_one);
  reconciliation_id := public.reconcile_import_batch(batch_one);
  retry_reconciliation_id := public.reconcile_import_batch(batch_one);
  perform pg_temp.assert_true(reconciliation_id = retry_reconciliation_id, 'AUD-02 reconciliation retry returns the existing result without an FK failure');
  perform pg_temp.assert_true((select status = 'MATCHED' from public.import_reconciliations where id = reconciliation_id), 'exact row and amount reconciliation passes');
  perform pg_temp.assert_true((select expected_control_totals = '{"amount":15.75}'::jsonb and actual_control_totals = '{"amount":15.75}'::jsonb from public.import_reconciliations where id = reconciliation_id), 'reconciliation stores canonical expected and actual totals');
  candidate_one := public.create_candidate_publication(batch_one, '{"test":"first"}');
  publication_one := public.publish_candidate(candidate_one, null);
  perform pg_temp.assert_true((select active_publication_id = publication_one from public.publication_heads where source_kind = 'SYNTHETIC_IMPORT' and scope_key = '2026-08'), 'first publication becomes active');

  batch_two := (public.create_import_batch(contract_id, '2026-08', 'Data', '["id","amount"]', repeat('e', 64), 124, 1, 1, '{"amount":20}')).id;
  reset role; set local role service_role; set local request.jwt.claim.role = 'service_role';
  perform public.verify_import_source_hash(batch_two, repeat('e', 64), 124);
  reset role; set local role authenticated; set local request.jwt.claim.role = 'authenticated'; perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform public.stage_import_chunk(batch_two, 0, 0, public.import_chunk_payload_hash('[{"id":"3","amount":"20"}]'), 1, '[{"id":"3","amount":"20"}]');
  perform public.validate_import_batch(batch_two); perform public.reconcile_import_batch(batch_two);
  candidate_two := public.create_candidate_publication(batch_two, '{"test":"second"}');
  rejected := false;
  begin perform public.publish_candidate(candidate_two, '00000000-0000-0000-0000-000000000000'); exception when serialization_failure then rejected := true; end;
  perform pg_temp.assert_true(rejected, 'stale publish is rejected');
  perform pg_temp.assert_true((select active_publication_id = publication_one from public.publication_heads where source_kind = 'SYNTHETIC_IMPORT' and scope_key = '2026-08'), 'failed publish preserves previous active publication');
  publication_two := public.publish_candidate(candidate_two, publication_one);
  perform pg_temp.assert_true((select version = 2 and active_publication_id = publication_two from public.publication_heads where source_kind = 'SYNTHETIC_IMPORT' and scope_key = '2026-08'), 'successful publish advances one version');
  perform pg_temp.assert_true((select superseded_at is not null from public.publications where id = publication_one), 'previous publication is retained and marked superseded');

  batch_bad := (public.create_import_batch(contract_id, 'bad-scope', 'Data', '["id","amount"]', repeat('1', 64), 125, 1, 1, '{"amount":99}')).id;
  reset role; set local role service_role; set local request.jwt.claim.role = 'service_role';
  perform public.verify_import_source_hash(batch_bad, repeat('1', 64), 125);
  reset role; set local role authenticated; set local request.jwt.claim.role = 'authenticated'; perform set_config('request.jwt.claim.sub', admin_id::text, true);
  perform public.stage_import_chunk(batch_bad, 0, 0, public.import_chunk_payload_hash('[{"id":"4","amount":"20"}]'), 1, '[{"id":"4","amount":"20"}]');
  perform public.validate_import_batch(batch_bad); perform public.reconcile_import_batch(batch_bad);
  perform pg_temp.assert_true((select status = 'FAILED' from public.import_batches where id = batch_bad), 'control-total difference blocks candidate publication');
  rejected := false;
  begin perform public.create_candidate_publication(batch_bad, '{"test":"blocked"}'); exception when others then rejected := true; end;
  perform pg_temp.assert_true(rejected, 'failed reconciliation cannot create a candidate publication');
  perform pg_temp.assert_true((select active_publication_id = publication_two from public.publication_heads where source_kind = 'SYNTHETIC_IMPORT' and scope_key = '2026-08'), 'failed candidate creation preserves the previous active publication');

  rejected := false;
  begin perform public.register_source_contract('SYNTHETIC_IMPORT', '1', 'Changed', '["id"]'::jsonb, '["id"]'::jsonb, '{}'::jsonb, 'FULL_REPLACE'::public.publication_mode); exception when unique_violation then rejected := true; end;
  perform pg_temp.assert_true(rejected, 'AUD-01 a used source-contract version cannot be redefined');
  reset role;
  rejected := false;
  begin update public.source_contract_versions set required_sheet = 'Changed' where id = contract_id; exception when others then rejected := true; end;
  perform pg_temp.assert_true(rejected, 'AUD-01 database trigger rejects direct mutation of a used source-contract definition');

  reset role; set local role authenticated; set local request.jwt.claim.role = 'authenticated'; perform set_config('request.jwt.claim.sub', viewer_id::text, true);
  rejected := false;
  begin perform public.stage_import_chunk(batch_bad, 1, 1, repeat('3', 64), 0, '[]'); exception when insufficient_privilege then rejected := true; end;
  perform pg_temp.assert_true(rejected, 'viewer cannot stage import data');
end;
$$;

rollback;
