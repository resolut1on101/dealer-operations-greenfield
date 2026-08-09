-- Package 00: serialize every first-admin attempt across all target UUIDs.
-- The transaction-scoped advisory lock is released automatically on commit/rollback.

create or replace function public.bootstrap_first_admin(target_user_id uuid)
returns public.application_role
language plpgsql
security definer
set search_path = public
as $$
declare
  target_role public.application_role;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'bootstrap_first_admin is restricted to the trusted service role'
      using errcode = '42501';
  end if;

  -- Lock before checking for any existing admin. This serializes calls for
  -- different target UUIDs, preventing two concurrent first-admin assignments.
  perform pg_advisory_xact_lock(hashtextextended('public.bootstrap_first_admin', 0));

  select role
  into target_role
  from public.user_profiles
  where user_id = target_user_id
  for update;

  if not found then
    raise exception 'Target user profile does not exist; provide the exact authenticated user UUID'
      using errcode = 'P0002';
  end if;

  if target_role = 'admin' then
    return 'admin';
  end if;

  if exists (select 1 from public.user_profiles where role = 'admin') then
    raise exception 'An admin already exists; bootstrap_first_admin cannot assign another one'
      using errcode = 'P0001';
  end if;

  update public.user_profiles
  set role = 'admin'
  where user_id = target_user_id;

  return 'admin';
end;
$$;

revoke all on function public.bootstrap_first_admin(uuid) from public;
revoke all on function public.bootstrap_first_admin(uuid) from anon;
revoke all on function public.bootstrap_first_admin(uuid) from authenticated;
grant execute on function public.bootstrap_first_admin(uuid) to service_role;

comment on function public.bootstrap_first_admin(uuid) is
  'Trusted, idempotent one-time first-admin bootstrap. A transaction-scoped global advisory lock serializes concurrent attempts.';
