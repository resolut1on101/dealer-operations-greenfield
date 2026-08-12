-- Package 02U: raw Customer Master provenance is an admin-only inspection surface.
-- Resolved customer read models retain their existing authenticated read policies.

drop policy if exists customer_master_snapshots_read on public.customer_master_snapshots;
drop policy if exists customer_master_observations_read on public.customer_master_observations;

create policy customer_master_snapshots_admin_read
on public.customer_master_snapshots
for select
to authenticated
using (public.is_admin());

create policy customer_master_observations_admin_read
on public.customer_master_observations
for select
to authenticated
using (public.is_admin());

-- Keep authenticated table privileges so the existing admin RLS policy can evaluate;
-- viewers remain RLS-hidden and service_role continues to bypass RLS as before.
grant select on public.customer_master_snapshots, public.customer_master_observations to authenticated;
