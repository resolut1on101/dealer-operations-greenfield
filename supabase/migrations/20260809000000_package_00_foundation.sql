-- Package 00 only: application identity and the two-role authorization foundation.
-- Business entities, publications and metrics belong to later packages.

create type public.application_role as enum ('admin', 'viewer');

create table public.user_profiles (
  user_id uuid primary key references auth.users (id) on delete cascade,
  role public.application_role not null default 'viewer',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_profiles enable row level security;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_profiles
    where user_id = auth.uid()
      and role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

create policy "authenticated_read"
on public.user_profiles
for select
to authenticated
using (true);

create policy "admin_write"
on public.user_profiles
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger user_profiles_set_updated_at
before update on public.user_profiles
for each row execute function public.set_updated_at();

comment on table public.user_profiles is
  'Package 00 identity foundation. Roles are intentionally limited to admin and viewer.';
