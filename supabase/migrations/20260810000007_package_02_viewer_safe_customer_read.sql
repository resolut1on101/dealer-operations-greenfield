-- Package 02U: separate the viewer customer workspace from Package 02
-- provenance, resolution, and organization-evidence base tables.

drop policy if exists customer_representatives_read on public.customer_representatives;
drop policy if exists customer_representative_ssm_resolutions_read on public.customer_representative_ssm_resolutions;
drop policy if exists customer_resolutions_read on public.customer_resolutions;
drop policy if exists customers_read on public.customers;

create policy customer_representatives_admin_read
on public.customer_representatives
for select
to authenticated
using (public.is_admin());

create policy customer_representative_ssm_resolutions_admin_read
on public.customer_representative_ssm_resolutions
for select
to authenticated
using (public.is_admin());

create policy customer_resolutions_admin_read
on public.customer_resolutions
for select
to authenticated
using (public.is_admin());

create policy customers_admin_read
on public.customers
for select
to authenticated
using (public.is_admin());

-- Explicitly bounded business read contract. It never returns snapshot IDs,
-- source observation IDs, raw candidates, or resolution evidence. The function
-- is SECURITY DEFINER because viewer RLS is intentionally denied on every base
-- table in this query.
create or replace function public.read_current_customer_business_surface()
returns table (
  customer_id text,
  customer_name text,
  trade_name text,
  status public.customer_status,
  channel public.customer_channel,
  segment text,
  representative text,
  chief text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    c.customer_id,
    c.customer_name,
    c.trade_name,
    c.status,
    c.channel,
    c.segment,
    case
      when cr.representative_resolution_state = 'RESOLVED' then representative.normalized_name
      else null
    end as representative,
    case
      when c.ssm_resolution_state = 'RESOLVED' then c.canonical_ssm
      else null
    end as chief
  from public.customers c
  left join public.customer_resolutions cr
    on cr.customer_id = c.customer_id
   and cr.snapshot_id = c.active_snapshot_id
  left join public.customer_representatives representative
    on representative.id = cr.representative_id
  where c.current_snapshot_state = 'PRESENT_IN_CURRENT_MASTER';
$$;

revoke all on function public.read_current_customer_business_surface() from public;
grant execute on function public.read_current_customer_business_surface() to authenticated;

-- Table privileges remain for RLS evaluation by authenticated admins. Viewer
-- access is denied by the admin-only policies above; the function is the only
-- viewer customer business read surface.
grant select on public.customer_representatives,
  public.customer_representative_ssm_resolutions,
  public.customer_resolutions,
  public.customers to authenticated;
