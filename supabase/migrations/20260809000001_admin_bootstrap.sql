-- Package 00: deterministic identity bootstrap and first-admin procedure.
-- No browser-accessible path can assign an administrative role.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_profiles (user_id, role)
  values (new.id, 'viewer')
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute function public.handle_new_user();

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
  'Trusted, idempotent one-time first-admin bootstrap. Requires the exact auth user UUID and service_role.';
