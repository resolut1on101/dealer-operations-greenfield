-- Synthetic load acceptance: normal 2.5K plus 10K/25K/50K batches, all using 1K set-based chunks.
begin;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void language plpgsql as $$ begin if condition is distinct from true then raise exception 'Assertion failed: %', message; end if; end; $$;

do $$
declare
  admin_id uuid := '40000000-0000-0000-0000-000000000001'; contract_id uuid; batch_id uuid; candidate_id uuid;
  total integer; chunk_count integer; chunk_no integer; row_offset integer; rows jsonb; started_at timestamptz; elapsed interval;
begin
  insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  values (admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'package01-load@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());
  update public.user_profiles set role = 'admin' where user_id = admin_id;
  set local role authenticated; set local request.jwt.claim.role = 'authenticated'; perform set_config('request.jwt.claim.sub', admin_id::text, true);
  contract_id := public.register_source_contract('SYNTHETIC_LOAD', '1', 'Data', '["id","amount"]'::jsonb, '["id","amount"]'::jsonb, '{"amount":"amount"}'::jsonb, '{"amount":0}'::jsonb, 'FULL_REPLACE'::public.publication_mode);

  foreach total in array array[2500, 10000, 25000, 50000] loop
    chunk_count := ceil(total::numeric / 1000)::integer;
    batch_id := (public.create_import_batch(contract_id, 'load-' || total, 'Data', '["id","amount"]'::jsonb,
      lpad(to_hex(total), 64, '0'), total, total, chunk_count,
      jsonb_build_object('amount', total))).id;
    reset role; set local role service_role; set local request.jwt.claim.role = 'service_role';
    perform public.verify_import_source_hash(batch_id, lpad(to_hex(total), 64, '0'), total);
    reset role; set local role authenticated; set local request.jwt.claim.role = 'authenticated'; perform set_config('request.jwt.claim.sub', admin_id::text, true);
    started_at := clock_timestamp();
    for chunk_no in 0..chunk_count - 1 loop
      row_offset := chunk_no * 1000;
      select jsonb_agg(jsonb_build_object('id', row_number::text, 'amount', '1')) into rows
      from generate_series(row_offset + 1, least(row_offset + 1000, total)) row_number;
      perform public.stage_import_chunk(batch_id, chunk_no, row_offset, public.import_chunk_payload_hash(rows), jsonb_array_length(rows), rows);
    end loop;
    perform public.validate_import_batch(batch_id); perform public.reconcile_import_batch(batch_id);
    candidate_id := public.create_candidate_publication(batch_id, jsonb_build_object('synthetic_rows', total));
    perform public.publish_candidate(candidate_id, null);
    elapsed := clock_timestamp() - started_at;
    perform pg_temp.assert_true((select status = 'PUBLISHED' from public.import_batches where id = batch_id), total || ' synthetic rows publish');
    raise notice 'Package 01 synthetic load rows=% chunks=% elapsed=%', total, chunk_count, elapsed;
  end loop;
end;
$$;

rollback;
