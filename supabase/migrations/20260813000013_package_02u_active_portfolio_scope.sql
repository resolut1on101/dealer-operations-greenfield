-- Package 02U: canonical active sales portfolio read surface.
-- This is deliberately read-only: raw customer observations and historical rows stay intact.

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
    public.customer_business_display_name(c.customer_name),
    c.trade_name,
    c.status,
    c.channel,
    c.segment,
    coalesce(
      (
        select nullif(btrim(raw_name), '')
        from jsonb_array_elements_text(representative.raw_names) as raw(raw_name)
        where nullif(btrim(raw_name), '') is not null
        order by raw_name collate "C"
        limit 1
      ),
      representative.normalized_name
    ) as representative,
    c.canonical_ssm as chief
  from public.customers c
  join public.customer_resolutions cr
    on cr.customer_id = c.customer_id
   and cr.snapshot_id = c.active_snapshot_id
   and cr.representative_resolution_state = 'RESOLVED'
  join public.customer_representatives representative
    on representative.id = cr.representative_id
  where c.current_snapshot_state = 'PRESENT_IN_CURRENT_MASTER'
    and c.status = 'ACTIVE'
    and c.ssm_resolution_state = 'RESOLVED'
    and nullif(btrim(c.canonical_ssm), '') is not null;
$$;

revoke all on function public.read_current_customer_business_surface() from public;
grant execute on function public.read_current_customer_business_surface() to authenticated;
