-- Package 03A — Malzemeler / current warehouse stock snapshot.
-- The source is an operational FULL_REPLACE snapshot. Product split/package codes
-- are normalized through the accepted Package 03 canonical product reference before
-- any business row is exposed. Exact quantities remain calculation truth.

-- Migration-owned source contract. The browser also requires this exact ordered
-- three-column signature; the database re-checks it before publication materializes.
do $$
begin
  perform public.register_system_source_contract(
    'WAREHOUSE_STOCK', '1', 'SAPUI5 dışa aktarımı',
    '["Malzeme numarası","Malzeme tanımı","Tahditsiz kullanılabilir"]'::jsonb,
    '["Malzeme numarası","Malzeme tanımı","Tahditsiz kullanılabilir"]'::jsonb,
    '{"available_quantity_checksum":"Tahditsiz kullanılabilir"}'::jsonb,
    '{"available_quantity_checksum":6}'::jsonb,
    'FULL_REPLACE'::public.publication_mode
  );
end;
$$;

create table if not exists public.warehouse_stock_runs (
  id uuid primary key default gen_random_uuid(),
  scope_key text not null,
  publication_id uuid not null unique references public.publications(id) on delete restrict,
  batch_id uuid not null unique references public.import_batches(id) on delete restrict,
  source_file_hash text not null check (source_file_hash ~ '^[a-f0-9]{64}$'),
  raw_row_count integer not null check (raw_row_count >= 0),
  business_row_count integer not null check (business_row_count >= 0),
  created_at timestamptz not null default now()
);

create table if not exists public.warehouse_stock_raw_rows (
  run_id uuid not null references public.warehouse_stock_runs(id) on delete cascade,
  source_row_no bigint not null check (source_row_no > 0),
  raw_product_code text not null check (raw_product_code ~ '^[0-9]+$'),
  raw_product_name text not null check (btrim(raw_product_name) <> ''),
  raw_available_quantity numeric not null,
  canonical_product_code text not null check (canonical_product_code ~ '^[0-9]+$'),
  canonical_quantity_numerator bigint not null check (canonical_quantity_numerator > 0),
  canonical_quantity_denominator bigint not null check (canonical_quantity_denominator > 0),
  exact_canonical_quantity numeric not null,
  normalization_policy text not null check (normalization_policy in ('STANDARD','HIGH_ALCOHOL','IDENTITY')),
  primary key (run_id, source_row_no),
  unique (run_id, raw_product_code)
);

create table if not exists public.warehouse_stock_canonical_rows (
  run_id uuid not null references public.warehouse_stock_runs(id) on delete cascade,
  scope_key text not null,
  canonical_product_code text not null check (canonical_product_code ~ '^[0-9]+$'),
  canonical_product_name text,
  exact_available_quantity numeric not null,
  raw_row_count integer not null check (raw_row_count > 0),
  hidden_split_row_count integer not null check (hidden_split_row_count >= 0),
  primary key (run_id, canonical_product_code),
  check (canonical_product_name is null or btrim(canonical_product_name) <> '')
);

create table if not exists public.warehouse_stock_heads (
  scope_key text primary key,
  active_run_id uuid not null references public.warehouse_stock_runs(id) on delete restrict,
  updated_at timestamptz not null default now()
);

create index if not exists warehouse_stock_runs_scope_created_idx
  on public.warehouse_stock_runs(scope_key, created_at desc);
create index if not exists warehouse_stock_raw_rows_canonical_idx
  on public.warehouse_stock_raw_rows(run_id, canonical_product_code);
create index if not exists warehouse_stock_canonical_rows_scope_idx
  on public.warehouse_stock_canonical_rows(scope_key, canonical_product_code);

alter table public.warehouse_stock_runs enable row level security;
alter table public.warehouse_stock_raw_rows enable row level security;
alter table public.warehouse_stock_canonical_rows enable row level security;
alter table public.warehouse_stock_heads enable row level security;

drop policy if exists warehouse_stock_runs_admin_read on public.warehouse_stock_runs;
drop policy if exists warehouse_stock_raw_rows_admin_read on public.warehouse_stock_raw_rows;
drop policy if exists warehouse_stock_canonical_rows_admin_read on public.warehouse_stock_canonical_rows;
drop policy if exists warehouse_stock_heads_admin_read on public.warehouse_stock_heads;

create policy warehouse_stock_runs_admin_read
  on public.warehouse_stock_runs for select to authenticated using (public.is_admin());
create policy warehouse_stock_raw_rows_admin_read
  on public.warehouse_stock_raw_rows for select to authenticated using (public.is_admin());
create policy warehouse_stock_canonical_rows_admin_read
  on public.warehouse_stock_canonical_rows for select to authenticated using (public.is_admin());
create policy warehouse_stock_heads_admin_read
  on public.warehouse_stock_heads for select to authenticated using (public.is_admin());

revoke all on table public.warehouse_stock_runs, public.warehouse_stock_raw_rows,
  public.warehouse_stock_canonical_rows, public.warehouse_stock_heads
  from public, anon, authenticated;
grant select on table public.warehouse_stock_runs, public.warehouse_stock_raw_rows,
  public.warehouse_stock_canonical_rows, public.warehouse_stock_heads
  to authenticated;

create or replace function public.materialize_current_warehouse_stock(p_publication_id uuid)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
declare
  v_publication public.publications;
  v_batch public.import_batches;
  v_run_id uuid;
  v_ref_id uuid;
  v_business_rows integer;
  v_exact_headers constant jsonb := '["Malzeme numarası","Malzeme tanımı","Tahditsiz kullanılabilir"]'::jsonb;
begin
  select * into v_publication
  from public.publications
  where id = p_publication_id;
  if not found then
    raise exception 'Warehouse stock publication was not found' using errcode='P0002';
  end if;
  if v_publication.source_kind <> 'WAREHOUSE_STOCK' then
    raise exception 'WAREHOUSE_STOCK publication is required' using errcode='22023';
  end if;

  select b.* into v_batch
  from public.candidate_publications cp
  join public.import_batches b on b.id = cp.batch_id
  where cp.id = v_publication.candidate_id;
  if not found or v_batch.published_publication_id is distinct from v_publication.id or v_batch.status <> 'PUBLISHED' then
    raise exception 'Published WAREHOUSE_STOCK batch is required' using errcode='55000';
  end if;
  if v_batch.scope_key is null or btrim(v_batch.scope_key) = '' then
    raise exception 'Warehouse stock scope is required' using errcode='22023';
  end if;
  if v_batch.source_sheet <> 'SAPUI5 dışa aktarımı' or v_batch.source_headers is distinct from v_exact_headers then
    raise exception 'WAREHOUSE_STOCK requires the exact ordered three-column Malzemeler signature' using errcode='22023';
  end if;

  if exists (
    select 1 from public.staging_rows s
    where s.batch_id = v_batch.id and s.row_status <> 'VALID'
  ) or (select count(*) from public.staging_rows s where s.batch_id=v_batch.id) <> v_batch.expected_rows then
    raise exception 'WAREHOUSE_STOCK requires every source row to be valid; duplicate/excluded/blocked rows are not publishable' using errcode='23514';
  end if;

  if exists (
    select 1
    from public.staging_rows s
    where s.batch_id=v_batch.id
      and (
        nullif(btrim(s.payload->>'Malzeme numarası'),'') is null
        or btrim(s.payload->>'Malzeme numarası') !~ '^[0-9]+$'
        or nullif(btrim(s.payload->>'Malzeme tanımı'),'') is null
        or coalesce(s.payload->>'Tahditsiz kullanılabilir','') !~ '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$'
      )
  ) then
    raise exception 'WAREHOUSE_STOCK contains an invalid product code, product name, or available quantity' using errcode='22023';
  end if;

  if exists (
    select 1
    from public.staging_rows s
    where s.batch_id=v_batch.id
    group by btrim(s.payload->>'Malzeme numarası')
    having count(*) > 1
  ) then
    raise exception 'WAREHOUSE_STOCK contains duplicate material codes; current stock rows are never auto-summed by raw code' using errcode='23505';
  end if;

  select id into v_ref_id
  from public.product_conversion_reference_versions
  where scope_key=btrim(v_batch.scope_key) and is_active;
  if v_ref_id is null then
    raise exception 'Active canonical product reference is required before warehouse stock publication' using errcode='55000';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('warehouse-stock:' || btrim(v_batch.scope_key),0));

  insert into public.warehouse_stock_runs(
    scope_key, publication_id, batch_id, source_file_hash, raw_row_count, business_row_count
  ) values (
    btrim(v_batch.scope_key), v_publication.id, v_batch.id, v_batch.verified_file_hash,
    v_batch.expected_rows::integer, 0
  )
  returning id into v_run_id;

  insert into public.warehouse_stock_raw_rows(
    run_id,source_row_no,raw_product_code,raw_product_name,raw_available_quantity,
    canonical_product_code,canonical_quantity_numerator,canonical_quantity_denominator,
    exact_canonical_quantity,normalization_policy
  )
  select
    v_run_id,
    s.source_row_no,
    btrim(s.payload->>'Malzeme numarası'),
    btrim(s.payload->>'Malzeme tanımı'),
    (s.payload->>'Tahditsiz kullanılabilir')::numeric,
    coalesce(m.canonical_product_code,btrim(s.payload->>'Malzeme numarası')),
    coalesce(m.canonical_quantity_numerator,1::bigint),
    coalesce(m.canonical_quantity_denominator,1::bigint),
    (s.payload->>'Tahditsiz kullanılabilir')::numeric
      * coalesce(m.canonical_quantity_numerator,1::bigint)::numeric
      / coalesce(m.canonical_quantity_denominator,1::bigint)::numeric,
    coalesce(m.normalization_policy,'IDENTITY')
  from public.staging_rows s
  left join public.product_canonical_mappings m
    on m.reference_version_id=v_ref_id
   and m.raw_product_code=btrim(s.payload->>'Malzeme numarası')
  where s.batch_id=v_batch.id and s.row_status='VALID';

  insert into public.warehouse_stock_canonical_rows(
    run_id,scope_key,canonical_product_code,canonical_product_name,exact_available_quantity,
    raw_row_count,hidden_split_row_count
  )
  select
    v_run_id,
    btrim(v_batch.scope_key),
    r.canonical_product_code,
    max(r.raw_product_name) filter (where r.raw_product_code=r.canonical_product_code),
    sum(r.exact_canonical_quantity),
    count(*)::integer,
    count(*) filter (where r.raw_product_code<>r.canonical_product_code)::integer
  from public.warehouse_stock_raw_rows r
  where r.run_id=v_run_id
  group by r.canonical_product_code;

  select count(*)::integer into v_business_rows
  from public.warehouse_stock_canonical_rows
  where run_id=v_run_id;
  update public.warehouse_stock_runs set business_row_count=v_business_rows where id=v_run_id;

  insert into public.warehouse_stock_heads(scope_key,active_run_id,updated_at)
  values(btrim(v_batch.scope_key),v_run_id,clock_timestamp())
  on conflict(scope_key) do update set
    active_run_id=excluded.active_run_id,
    updated_at=excluded.updated_at;

  return v_run_id;
end;
$$;

create or replace function public.read_current_warehouse_stock()
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
  ), current_lpu as (
    select l.*, ch.scope_key
    from current_heads ch
    cross join lateral public.current_canonical_product_lpu(ch.scope_key) l
  )
  select
    c.scope_key,
    c.canonical_product_code,
    c.canonical_product_name,
    c.exact_available_quantity,
    l.active_lpu,
    case when l.active_lpu is null then null
         else c.exact_available_quantity * l.active_lpu end,
    case when l.active_lpu is null then 'PARTIAL' else 'RESOLVED' end,
    ch.published_at
  from current_heads ch
  join public.warehouse_stock_canonical_rows c on c.run_id=ch.active_run_id
  left join current_lpu l
    on l.scope_key=c.scope_key and l.canonical_product_code=c.canonical_product_code
  order by c.canonical_product_code;
$$;

create or replace function public.read_current_warehouse_stock_summary()
returns table (
  scope_key text,
  business_row_count integer,
  litre_resolved_count integer,
  litre_partial_count integer,
  source_published_at timestamptz
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with current_heads as (
    select h.scope_key, h.active_run_id, r.business_row_count, p.published_at
    from public.warehouse_stock_heads h
    join public.warehouse_stock_runs r on r.id=h.active_run_id
    join public.publications p on p.id=r.publication_id
  ), current_lpu as (
    select l.*, ch.scope_key
    from current_heads ch
    cross join lateral public.current_canonical_product_lpu(ch.scope_key) l
  )
  select
    ch.scope_key,
    ch.business_row_count,
    count(*) filter (where l.active_lpu is not null)::integer,
    count(*) filter (where l.active_lpu is null)::integer,
    ch.published_at
  from current_heads ch
  join public.warehouse_stock_canonical_rows c on c.run_id=ch.active_run_id
  left join current_lpu l
    on l.scope_key=c.scope_key and l.canonical_product_code=c.canonical_product_code
  group by ch.scope_key, ch.business_row_count, ch.published_at;
$$;

revoke all on function public.materialize_current_warehouse_stock(uuid) from public, anon, authenticated, service_role;
revoke all on function public.read_current_warehouse_stock() from public, anon;
revoke all on function public.read_current_warehouse_stock_summary() from public, anon;
grant execute on function public.read_current_warehouse_stock() to authenticated;
grant execute on function public.read_current_warehouse_stock_summary() to authenticated;

comment on function public.read_current_warehouse_stock() is
'Viewer-safe current warehouse stock business surface. Split/package raw codes are collapsed to canonical products; exact quantity is never display-rounded and missing LPU yields NULL litres.';
comment on function public.read_current_warehouse_stock_summary() is
'Viewer-safe current warehouse snapshot coverage. Raw split-code counts remain admin/audit evidence and are not exposed on the normal business summary.';

-- Extend the Package 01 publication hook without changing the accepted transport semantics.
-- Warehouse materialization is in the same transaction as publication: if the stock
-- domain invariant fails, the new publication/head is rolled back atomically.
create or replace function public.publish_candidate(p_candidate_id uuid, p_expected_active_publication_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_candidate public.candidate_publications; v_batch public.import_batches; v_reconciliation public.import_reconciliations;
declare v_head public.publication_heads; v_publication_id uuid; v_next_version integer; v_has_head boolean;
begin
  perform public.assert_import_admin();
  select * into v_candidate from public.candidate_publications where id=p_candidate_id for update;
  if not found then raise exception 'Candidate publication was not found' using errcode='P0002'; end if;
  if v_candidate.status='PUBLISHED' then select id into v_publication_id from public.publications where candidate_id=p_candidate_id; return v_publication_id; end if;
  select * into v_batch from public.import_batches where id=v_candidate.batch_id for update;

  if v_batch.source_kind='PRODUCT_CONVERSION' then
    raise exception 'PRODUCT_CONVERSION is retired: paket.xlsx is internal reference evidence and cannot be published as a runtime upload source'
      using errcode='55000';
  end if;

  select * into v_reconciliation from public.import_reconciliations where id=v_candidate.reconciliation_id;
  if v_candidate.status<>'READY' or v_batch.status<>'CANDIDATE_READY' or v_reconciliation.status<>'MATCHED' then
    raise exception 'Candidate is stale, blocked, or not reconciled' using errcode='55000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('package01:' || v_batch.source_kind || ':' || v_batch.scope_key,0));
  select * into v_head from public.publication_heads where source_kind=v_batch.source_kind and scope_key=v_batch.scope_key for update;
  v_has_head:=found;
  if v_has_head and v_head.active_publication_id is distinct from p_expected_active_publication_id then
    raise exception 'Active publication changed; refresh and retry with its current id' using errcode='40001';
  end if;
  if not v_has_head and p_expected_active_publication_id is not null then raise exception 'No active publication exists for the expected id' using errcode='40001'; end if;
  v_next_version:=coalesce(v_head.version,0)+1;
  insert into public.publications(candidate_id,source_kind,scope_key,version,manifest,published_by)
  values(v_candidate.id,v_batch.source_kind,v_batch.scope_key,v_next_version,v_candidate.manifest,auth.uid())
  returning id into v_publication_id;
  if v_has_head then update public.publications set superseded_at=now() where id=v_head.active_publication_id; end if;
  insert into public.publication_heads(source_kind,scope_key,active_publication_id,version)
  values(v_batch.source_kind,v_batch.scope_key,v_publication_id,v_next_version)
  on conflict(source_kind,scope_key) do update set active_publication_id=excluded.active_publication_id,version=excluded.version,updated_at=now();
  update public.candidate_publications set status='PUBLISHED',published_at=now() where id=v_candidate.id;
  update public.import_batches set status='PUBLISHED',published_publication_id=v_publication_id,completed_at=now() where id=v_batch.id;
  perform pg_notify('publication_changed',json_build_object('source_kind',v_batch.source_kind,'scope_key',v_batch.scope_key,'publication_id',v_publication_id,'version',v_next_version)::text);

  if v_batch.source_kind in ('SELLOUT','KA_DELIVERY') then
    begin
      perform public.reconcile_product_domain_freshness(v_batch.scope_key);
    exception when others then
      insert into public.product_domain_heads(
        scope_key,active_run_id,freshness_state,freshness_error,stale_since,last_attempted_at,
        expected_conversion_publication_id,expected_sellout_publication_id,expected_ka_publication_id,updated_at
      ) values (
        v_batch.scope_key,null,'BLOCKED',sqlerrm,clock_timestamp(),clock_timestamp(),null,
        (select active_publication_id from public.publication_heads where source_kind='SELLOUT' and scope_key=v_batch.scope_key),
        (select active_publication_id from public.publication_heads where source_kind='KA_DELIVERY' and scope_key=v_batch.scope_key),
        clock_timestamp()
      )
      on conflict(scope_key) do update set
        active_run_id=null,freshness_state='BLOCKED',freshness_error=excluded.freshness_error,
        stale_since=coalesce(public.product_domain_heads.stale_since,excluded.stale_since),
        last_attempted_at=excluded.last_attempted_at,expected_conversion_publication_id=null,
        expected_sellout_publication_id=excluded.expected_sellout_publication_id,
        expected_ka_publication_id=excluded.expected_ka_publication_id,updated_at=excluded.updated_at;
    end;
  end if;

  if v_batch.source_kind='WAREHOUSE_STOCK' then
    perform public.materialize_current_warehouse_stock(v_publication_id);
  end if;

  return v_publication_id;
end;
$$;

comment on table public.warehouse_stock_raw_rows is
'Admin/audit-only raw current-stock transformation evidence. Raw split codes never become separate normal business rows.';
comment on table public.warehouse_stock_canonical_rows is
'Exact canonical warehouse quantities by current FULL_REPLACE stock publication. Litre is resolved dynamically from current Package 03 canonical LPU evidence.';
