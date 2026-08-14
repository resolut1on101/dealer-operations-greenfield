-- Package 03AU — viewer-safe warehouse stock UX surface and admin-approved persistent LPU overrides.
-- Package 03A remains the accepted import/canonicalization source of truth. This package adds an
-- effective business/presentation layer without exposing raw transformation evidence.

create table if not exists public.warehouse_stock_lpu_overrides (
  scope_key text not null check (length(btrim(scope_key)) > 0),
  canonical_product_code text not null check (canonical_product_code ~ '^[0-9]+$'),
  lpu numeric not null check (lpu > 0),
  created_by uuid not null references auth.users(id),
  updated_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (scope_key, canonical_product_code)
);

create table if not exists public.warehouse_stock_lpu_override_audit (
  id uuid primary key default gen_random_uuid(),
  scope_key text not null check (length(btrim(scope_key)) > 0),
  canonical_product_code text not null check (canonical_product_code ~ '^[0-9]+$'),
  old_effective_lpu numeric check (old_effective_lpu is null or old_effective_lpu > 0),
  new_lpu numeric not null check (new_lpu > 0),
  changed_by uuid not null references auth.users(id),
  changed_at timestamptz not null default now()
);

create index if not exists warehouse_stock_lpu_override_audit_product_idx
  on public.warehouse_stock_lpu_override_audit(scope_key, canonical_product_code, changed_at desc);

alter table public.warehouse_stock_lpu_overrides enable row level security;
alter table public.warehouse_stock_lpu_override_audit enable row level security;

drop policy if exists warehouse_stock_lpu_overrides_admin_read on public.warehouse_stock_lpu_overrides;
drop policy if exists warehouse_stock_lpu_override_audit_admin_read on public.warehouse_stock_lpu_override_audit;
create policy warehouse_stock_lpu_overrides_admin_read
  on public.warehouse_stock_lpu_overrides for select to authenticated using (public.is_admin());
create policy warehouse_stock_lpu_override_audit_admin_read
  on public.warehouse_stock_lpu_override_audit for select to authenticated using (public.is_admin());

revoke all on table public.warehouse_stock_lpu_overrides, public.warehouse_stock_lpu_override_audit
  from public, anon, authenticated;
grant select on table public.warehouse_stock_lpu_overrides, public.warehouse_stock_lpu_override_audit
  to authenticated;

create or replace function public.current_effective_canonical_product_lpu(p_scope_key text)
returns table (
  canonical_product_code text,
  source_lpu numeric,
  manual_lpu numeric,
  effective_lpu numeric,
  effective_source text
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with source_lpu as (
    select l.canonical_product_code, l.active_lpu
    from public.current_canonical_product_lpu(btrim(p_scope_key)) l
  ), product_keys as (
    select canonical_product_code from source_lpu
    union
    select o.canonical_product_code
    from public.warehouse_stock_lpu_overrides o
    where o.scope_key=btrim(p_scope_key)
  )
  select
    k.canonical_product_code,
    s.active_lpu,
    o.lpu,
    coalesce(o.lpu,s.active_lpu),
    case when o.lpu is not null then 'APPROVED_MANUAL'
         when s.active_lpu is not null then 'SOURCE_EVIDENCE'
         else null end
  from product_keys k
  left join source_lpu s using (canonical_product_code)
  left join public.warehouse_stock_lpu_overrides o
    on o.scope_key=btrim(p_scope_key) and o.canonical_product_code=k.canonical_product_code;
$$;

create or replace function public.read_current_warehouse_stock_ui()
returns table (
  scope_key text,
  product_code text,
  product_name text,
  exact_available_quantity numeric,
  lpu numeric,
  available_litres numeric,
  litre_resolution_state text,
  source_published_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with current_heads as (
    select h.scope_key, h.active_run_id, p.published_at
    from public.warehouse_stock_heads h
    join public.warehouse_stock_runs r on r.id=h.active_run_id
    join public.publications p on p.id=r.publication_id
  ), effective_lpu as (
    select l.*, ch.scope_key
    from current_heads ch
    cross join lateral public.current_effective_canonical_product_lpu(ch.scope_key) l
  )
  select
    c.scope_key,
    c.canonical_product_code,
    c.canonical_product_name,
    c.exact_available_quantity,
    l.effective_lpu,
    case when l.effective_lpu is null then null
         else c.exact_available_quantity * l.effective_lpu end,
    case when l.effective_lpu is null then 'PARTIAL' else 'RESOLVED' end,
    ch.published_at
  from current_heads ch
  join public.warehouse_stock_canonical_rows c on c.run_id=ch.active_run_id
  left join effective_lpu l
    on l.scope_key=c.scope_key and l.canonical_product_code=c.canonical_product_code
  order by c.canonical_product_code;
$$;

create or replace function public.read_current_warehouse_stock_ui_summary()
returns table (
  scope_key text,
  business_row_count integer,
  total_available_litres numeric,
  total_litres_state text,
  litre_resolved_count integer,
  litre_partial_count integer,
  source_published_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    s.scope_key,
    count(*)::integer,
    case when count(*) filter (where s.exact_available_quantity <> 0 and s.lpu is null) > 0 then null
         else coalesce(sum(coalesce(s.available_litres,0)),0) end,
    case when count(*) filter (where s.exact_available_quantity <> 0 and s.lpu is null) > 0 then 'PARTIAL'
         else 'RESOLVED' end,
    count(*) filter (where s.lpu is not null)::integer,
    count(*) filter (where s.lpu is null)::integer,
    max(s.source_published_at)
  from public.read_current_warehouse_stock_ui() s
  group by s.scope_key;
$$;

create or replace function public.set_warehouse_stock_lpu_overrides(
  p_scope_key text,
  p_updates jsonb,
  p_confirm_large_change boolean default false
)
returns table (
  updated_count integer,
  remaining_missing_count integer
)
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_scope text := btrim(p_scope_key);
  v_item record;
  v_old_effective numeric;
  v_updated integer := 0;
  v_remaining integer := 0;
begin
  perform public.assert_import_admin();
  if v_scope is null or v_scope='' then
    raise exception 'Warehouse stock scope is required' using errcode='22023';
  end if;
  if p_updates is null or jsonb_typeof(p_updates) <> 'array' then
    raise exception 'Litre / Birim updates must be a JSON array' using errcode='22023';
  end if;
  if exists (
    select 1
    from jsonb_to_recordset(p_updates) as x(product_code text,lpu numeric)
    group by btrim(x.product_code)
    having count(*) > 1
  ) then
    raise exception 'Duplicate product codes are not allowed in one Litre / Birim update' using errcode='23505';
  end if;

  for v_item in
    select btrim(x.product_code) as product_code, x.lpu
    from jsonb_to_recordset(p_updates) as x(product_code text,lpu numeric)
  loop
    if v_item.product_code is null or v_item.product_code !~ '^[0-9]+$' or v_item.lpu is null or v_item.lpu <= 0 then
      raise exception 'Every Litre / Birim update requires a numeric product code and a positive value' using errcode='22023';
    end if;
    if not exists (
      select 1
      from public.warehouse_stock_heads h
      join public.warehouse_stock_canonical_rows c on c.run_id=h.active_run_id
      where h.scope_key=v_scope and c.canonical_product_code=v_item.product_code
    ) then
      raise exception 'Product % is not present in the current warehouse stock scope %', v_item.product_code, v_scope using errcode='P0002';
    end if;

    select s.lpu into v_old_effective
    from public.read_current_warehouse_stock_ui() s
    where s.scope_key=v_scope and s.product_code=v_item.product_code;

    if v_old_effective is not null
       and abs(v_item.lpu-v_old_effective)/v_old_effective >= 0.25
       and not p_confirm_large_change then
      raise exception 'LPU_CONFIRM_REQUIRED:%:%:%', v_item.product_code, v_old_effective, v_item.lpu using errcode='22023';
    end if;

    if v_old_effective is distinct from v_item.lpu then
      insert into public.warehouse_stock_lpu_overrides(
        scope_key,canonical_product_code,lpu,created_by,updated_by
      ) values (
        v_scope,v_item.product_code,v_item.lpu,auth.uid(),auth.uid()
      )
      on conflict(scope_key,canonical_product_code) do update set
        lpu=excluded.lpu,
        updated_by=auth.uid(),
        updated_at=clock_timestamp();

      insert into public.warehouse_stock_lpu_override_audit(
        scope_key,canonical_product_code,old_effective_lpu,new_lpu,changed_by
      ) values (
        v_scope,v_item.product_code,v_old_effective,v_item.lpu,auth.uid()
      );
      v_updated := v_updated + 1;
    end if;
  end loop;

  select count(*)::integer into v_remaining
  from public.read_current_warehouse_stock_ui() s
  where s.scope_key=v_scope and s.lpu is null;

  return query select v_updated,v_remaining;
end;
$$;

revoke all on function public.current_effective_canonical_product_lpu(text) from public, anon, authenticated;
revoke all on function public.read_current_warehouse_stock_ui() from public, anon;
revoke all on function public.read_current_warehouse_stock_ui_summary() from public, anon;
revoke all on function public.set_warehouse_stock_lpu_overrides(text,jsonb,boolean) from public, anon;
grant execute on function public.read_current_warehouse_stock_ui() to authenticated;
grant execute on function public.read_current_warehouse_stock_ui_summary() to authenticated;
grant execute on function public.set_warehouse_stock_lpu_overrides(text,jsonb,boolean) to authenticated;

comment on table public.warehouse_stock_lpu_overrides is
'Package 03AU persistent admin-approved Litre / Birim master overrides. FULL_REPLACE warehouse stock publications never delete these values.';
comment on table public.warehouse_stock_lpu_override_audit is
'Package 03AU audit-only history for manual Litre / Birim changes. Not exposed in the normal warehouse stock UI.';
comment on function public.read_current_warehouse_stock_ui() is
'Package 03AU viewer-safe current warehouse stock surface. Manual approved LPU overrides take precedence over source evidence; missing LPU remains NULL.';
comment on function public.read_current_warehouse_stock_ui_summary() is
'Package 03AU authoritative UI summary. Total litres is NULL while any non-zero current stock row lacks LPU; the client must never fabricate a partial official total.';
comment on function public.set_warehouse_stock_lpu_overrides(text,jsonb,boolean) is
'Package 03AU admin-only persistent LPU master mutation with audit history and server-enforced 25 percent large-change confirmation.';
