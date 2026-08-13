-- Package 02U: lightweight metadata and organization aggregates for the active portfolio.
-- Keeps the browser from downloading the full customer universe just to build counts,
-- filter options, and organization analytics. Raw/history/provenance remain untouched.

create or replace function public.read_current_customer_portfolio_metadata()
returns table (
  total_count bigint,
  open_count bigint,
  closed_count bigint,
  unclassified_count bigint,
  channels text[],
  segments text[],
  representatives text[],
  chiefs text[]
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with surface as materialized (
    select *
    from public.read_current_customer_business_surface()
  )
  select
    count(*)::bigint as total_count,
    count(*) filter (where channel = 'OPEN')::bigint as open_count,
    count(*) filter (where channel = 'CLOSED')::bigint as closed_count,
    count(*) filter (where channel = 'UNCLASSIFIED')::bigint as unclassified_count,
    coalesce(
      array_agg(distinct channel::text order by channel::text)
        filter (where nullif(btrim(channel::text), '') is not null),
      array[]::text[]
    ) as channels,
    coalesce(
      array_agg(distinct segment order by segment)
        filter (where nullif(btrim(segment), '') is not null),
      array[]::text[]
    ) as segments,
    coalesce(
      array_agg(distinct representative order by representative)
        filter (where nullif(btrim(representative), '') is not null),
      array[]::text[]
    ) as representatives,
    coalesce(
      array_agg(distinct chief order by chief)
        filter (where nullif(btrim(chief), '') is not null),
      array[]::text[]
    ) as chiefs
  from surface;
$$;

revoke all on function public.read_current_customer_portfolio_metadata() from public;
grant execute on function public.read_current_customer_portfolio_metadata() to authenticated;

create or replace function public.read_current_customer_organization_aggregates()
returns table (
  chief text,
  representative text,
  channel public.customer_channel,
  segment text,
  customer_count bigint
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    surface.chief,
    surface.representative,
    surface.channel,
    surface.segment,
    count(*)::bigint as customer_count
  from public.read_current_customer_business_surface() as surface
  group by surface.chief, surface.representative, surface.channel, surface.segment
  order by surface.chief collate "C", surface.representative collate "C", surface.channel, surface.segment collate "C" nulls last;
$$;

revoke all on function public.read_current_customer_organization_aggregates() from public;
grant execute on function public.read_current_customer_organization_aggregates() to authenticated;
