-- Runs against a freshly reset local Supabase database in one transaction.
-- It intentionally rolls back all test users and profile mutations.

begin;

create or replace function pg_temp.assert_true(condition boolean, message text)
returns void
language plpgsql
as $$
begin
  if condition is distinct from true then
    raise exception 'Assertion failed: %', message;
  end if;
end;
$$;

do $$
declare
  viewer_id uuid := '10000000-0000-0000-0000-000000000001';
  admin_id uuid := '10000000-0000-0000-0000-000000000002';
  target_id uuid := '10000000-0000-0000-0000-000000000003';
  row_count integer;
  rejected boolean;
begin
  insert into auth.users (
    id, instance_id, aud, role, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values
    (viewer_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-viewer@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
    (admin_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rls-admin@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
    (target_id, '00000000-0000-0000-0000-000000000003', 'authenticated', 'authenticated', 'rls-target@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

  perform pg_temp.assert_true(
    (select count(*) = 3 from public.user_profiles where user_id in (viewer_id, admin_id, target_id)),
    'authenticated user creation produces deterministic user_profiles rows'
  );
  perform pg_temp.assert_true(
    (select count(*) = 3 from public.user_profiles where user_id in (viewer_id, admin_id, target_id) and role = 'viewer'),
    'new profiles default to viewer'
  );

  -- ANON cannot read or write.
  set local role anon;
  set local request.jwt.claim.role = 'anon';
  rejected := false;
  begin
    execute 'select 1 from public.user_profiles';
  exception when insufficient_privilege then rejected := true;
  end;
  perform pg_temp.assert_true(rejected, 'anon read is rejected');
  rejected := false;
  begin
    execute 'insert into public.user_profiles (user_id, role) values (''10000000-0000-0000-0000-000000000004'', ''viewer'')';
  exception when insufficient_privilege then rejected := true;
  end;
  perform pg_temp.assert_true(rejected, 'anon write is rejected');

  -- VIEWER can read all published/read-side foundation data but cannot mutate or self-escalate.
  reset role;
  set local role authenticated;
  set local request.jwt.claim.role = 'authenticated';
  set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000001';
  select count(*) into row_count from public.user_profiles;
  perform pg_temp.assert_true(row_count = 3, 'viewer authenticated read works');
  update public.user_profiles set role = 'admin' where user_id = viewer_id;
  get diagnostics row_count = row_count;
  perform pg_temp.assert_true(row_count = 0, 'viewer cannot self-escalate');
  delete from public.user_profiles where user_id = target_id;
  get diagnostics row_count = row_count;
  perform pg_temp.assert_true(row_count = 0, 'viewer delete is denied by RLS');
  rejected := false;
  begin
    execute 'insert into public.user_profiles (user_id, role) values (''10000000-0000-0000-0000-000000000004'', ''viewer'')';
  exception when insufficient_privilege then rejected := true;
  end;
  perform pg_temp.assert_true(rejected, 'viewer insert is rejected');

  -- A browser-authenticated caller cannot invoke the trusted bootstrap procedure.
  rejected := false;
  begin
    perform public.bootstrap_first_admin(admin_id);
  exception when insufficient_privilege then rejected := true;
  end;
  perform pg_temp.assert_true(rejected, 'authenticated caller cannot bootstrap admin');

  -- The trusted service role performs the one-time, exact-UUID bootstrap.
  reset role;
  set local role service_role;
  set local request.jwt.claim.role = 'service_role';
  perform pg_temp.assert_true(public.bootstrap_first_admin(admin_id) = 'admin', 'trusted bootstrap creates first admin');
  reset role;
  perform pg_temp.assert_true((select role = 'admin' from public.user_profiles where user_id = admin_id), 'exact bootstrap target is admin');
  set local role service_role;
  set local request.jwt.claim.role = 'service_role';
  perform pg_temp.assert_true(public.bootstrap_first_admin(admin_id) = 'admin', 'bootstrap is idempotent for the same admin');
  rejected := false;
  begin
    perform public.bootstrap_first_admin(target_id);
  exception when others then rejected := true;
  end;
  perform pg_temp.assert_true(rejected, 'bootstrap does not silently assign a second admin');

  -- ADMIN retains authenticated read and the allowed write path.
  reset role;
  set local role authenticated;
  set local request.jwt.claim.role = 'authenticated';
  set local request.jwt.claim.sub = '10000000-0000-0000-0000-000000000002';
  select count(*) into row_count from public.user_profiles;
  perform pg_temp.assert_true(row_count = 3, 'admin authenticated read works');
  update public.user_profiles set role = 'viewer' where user_id = target_id;
  get diagnostics row_count = row_count;
  perform pg_temp.assert_true(row_count = 1, 'admin allowed write works');
  delete from public.user_profiles where user_id = target_id;
  get diagnostics row_count = row_count;
  perform pg_temp.assert_true(row_count = 1, 'admin allowed delete works');

  -- The enum rejects all roles except admin and viewer.
  rejected := false;
  begin
    insert into public.user_profiles (user_id, role) values ('10000000-0000-0000-0000-000000000005', 'other'::public.application_role);
  exception when invalid_text_representation then rejected := true;
  end;
  perform pg_temp.assert_true(rejected, 'application_role rejects values outside admin/viewer');
end;
$$;

rollback;
