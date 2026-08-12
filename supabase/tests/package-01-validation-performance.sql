-- Validation performance regression: LIVE-equivalent 5,869 rows and 10K rows.
-- No candidate or publication is created; the transaction is rolled back.

begin;

create temp table validation_timings (
  rows_count integer not null,
  elapsed interval not null
) on commit drop;
grant insert, select on validation_timings to authenticated;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$
begin
  if condition is distinct from true then
    raise exception 'Assertion failed: %', message;
  end if;
end;
$$;

do $$
declare
  admin_id uuid := '50000000-0000-0000-0000-000000000001';
  contract_id uuid;
  batch_id uuid;
  total integer;
  chunk_count integer;
  chunk_no integer;
  row_offset integer;
  rows jsonb;
  started_at timestamptz;
  elapsed interval;
  reconciliation_id uuid;
  mixed_batch_id uuid;
  mixed_validation_id uuid;
  mixed_reconciliation_id uuid;
  control_batch_id uuid;
  control_validation_id uuid;
  control_contract_id uuid;
  rejected boolean;
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values (
    admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
    'package01-validation-performance@example.test', 'not-used', now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );
  update public.user_profiles set role = 'admin' where user_id = admin_id;

  set local role authenticated;
  set local request.jwt.claim.role = 'authenticated';
  perform set_config('request.jwt.claim.sub', admin_id::text, true);

  contract_id := public.register_source_contract(
    'SYNTHETIC_VALIDATION', '1', 'Data', '["id","amount"]'::jsonb,
    '["id","amount"]'::jsonb, '{"amount":"amount"}'::jsonb,
    '{"amount":0}'::jsonb, 'FULL_REPLACE'::public.publication_mode
  );

  foreach total in array array[5869, 10000] loop
    chunk_count := ceil(total::numeric / 1000)::integer;
    batch_id := (
      public.create_import_batch(
        contract_id, 'validation-' || total, 'Data', '["id","amount"]'::jsonb,
        lpad(to_hex(total), 64, '0'), total, total, chunk_count,
        jsonb_build_object('amount', total)
      )
    ).id;

    reset role;
    set local role service_role;
    set local request.jwt.claim.role = 'service_role';
    perform public.verify_import_source_hash(batch_id, lpad(to_hex(total), 64, '0'), total);

    reset role;
    set local role authenticated;
    set local request.jwt.claim.role = 'authenticated';
    perform set_config('request.jwt.claim.sub', admin_id::text, true);

    for chunk_no in 0..chunk_count - 1 loop
      row_offset := chunk_no * 1000;
      select jsonb_agg(jsonb_build_object('id', row_number::text, 'amount', '1'))
      into rows
      from generate_series(row_offset + 1, least(row_offset + 1000, total)) row_number;
      perform public.stage_import_chunk(
        batch_id, chunk_no, row_offset, public.import_chunk_payload_hash(rows),
        jsonb_array_length(rows), rows
      );
    end loop;

    started_at := clock_timestamp();
    perform public.validate_import_batch(batch_id);
    elapsed := clock_timestamp() - started_at;
    perform pg_temp.assert_true(
      elapsed < interval '8 seconds',
      total || ' rows validation stays below authenticated statement timeout'
    );
    perform pg_temp.assert_true(
      (select status = 'VALIDATED' from public.import_batches where id = batch_id),
      total || ' rows validation reaches VALIDATED'
    );
    insert into validation_timings(rows_count, elapsed) values (total, elapsed);

    reconciliation_id := public.reconcile_import_batch(batch_id);
    perform pg_temp.assert_true(
      (select status = 'MATCHED' from public.import_reconciliations where id = reconciliation_id),
      total || ' rows reconciliation remains MATCHED'
    );
    raise notice 'Package 01 validation performance rows=% elapsed=%', total, elapsed;
  end loop;

  mixed_batch_id := (
    public.create_import_batch(
      contract_id, 'validation-invalid-duplicate', 'Data', '["id","amount"]'::jsonb,
      repeat('b', 64), 3, 3, 1, jsonb_build_object('amount', 3)
    )
  ).id;
  reset role;
  set local role service_role;
  set local request.jwt.claim.role = 'service_role';
  perform public.verify_import_source_hash(mixed_batch_id, repeat('b', 64), 3);
  reset role;
  set local role authenticated;
  set local request.jwt.claim.role = 'authenticated';
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  rows := '[{"id":"1","amount":"1"},{"id":"1","amount":"1"},{"id":"","amount":"1"}]'::jsonb;
  perform public.stage_import_chunk(
    mixed_batch_id, 0, 0, public.import_chunk_payload_hash(rows),
    jsonb_array_length(rows), rows
  );
  mixed_validation_id := public.validate_import_batch(mixed_batch_id);
  perform pg_temp.assert_true(
    (select valid_rows = 1 and blocked_rows = 1 and duplicate_rows = 1
     from public.validation_runs where id = mixed_validation_id),
    'invalid row remains blocked and duplicate semantics remain stable'
  );
  mixed_reconciliation_id := public.reconcile_import_batch(mixed_batch_id);
  perform pg_temp.assert_true(
    (select status = 'MISMATCHED' from public.import_reconciliations where id = mixed_reconciliation_id),
    'blocked/duplicate batch cannot reconcile as matched'
  );
  rejected := false;
  begin
    perform public.create_candidate_publication(mixed_batch_id, '{"test":"invalid-duplicate"}');
  exception when others then
    rejected := true;
  end;
  perform pg_temp.assert_true(rejected, 'invalid/duplicate batch cannot create a candidate');

  control_contract_id := public.register_source_contract(
    'SYNTHETIC_VALIDATION_CONTROL',
    '1',
    'Data',
    '["id","amount"]'::jsonb,
    '["id","amount"]'::jsonb,
    '{"amount_total":"amount"}'::jsonb,
    '{"amount_total":0}'::jsonb,
    'FULL_REPLACE'::public.publication_mode
  );

  control_batch_id := (
    public.create_import_batch(
      control_contract_id, 'validation-invalid-control', 'Data', '["id","amount"]'::jsonb,
      repeat('c', 64), 3, 1, 1, jsonb_build_object('amount_total', 3)
    )
  ).id;
  reset role;
  set local role service_role;
  set local request.jwt.claim.role = 'service_role';
  perform public.verify_import_source_hash(control_batch_id, repeat('c', 64), 3);
  reset role;
  set local role authenticated;
  set local request.jwt.claim.role = 'authenticated';
  perform set_config('request.jwt.claim.sub', admin_id::text, true);
  rows := '[{"id":"2","amount":"not-a-number"}]'::jsonb;
  perform public.stage_import_chunk(
    control_batch_id, 0, 0, public.import_chunk_payload_hash(rows),
    jsonb_array_length(rows), rows
  );
  control_validation_id := public.validate_import_batch(control_batch_id);
  perform pg_temp.assert_true(
    (select valid_rows = 0 and blocked_rows = 1 from public.validation_runs where id = control_validation_id),
    'control-total-only blocker remains blocked without a required-field error'
  );
  perform pg_temp.assert_true(
    exists (
      select 1 from public.validation_issues
      where validation_run_id = control_validation_id
        and code = 'INVALID_CONTROL_TOTAL_FIELD'
        and detail -> 'source_row_no' = '1'::jsonb
        and detail -> 'missing_required_fields' = '[]'::jsonb
        and detail -> 'invalid_control_total_fields' = '["amount"]'::jsonb
    ),
    'control-total blocker persists exact field detail'
  );
end;
$$;

select rows_count, elapsed from validation_timings order by rows_count;

rollback;
