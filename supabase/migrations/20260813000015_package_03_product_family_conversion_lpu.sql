-- Package 03: canonical product family / variant / conversion / LPU domain.
-- Package 01 remains the only source transport/publication engine. This package
-- stores compact resolved product truth and edge aggregates; raw workbook rows
-- remain in Package 01 staging/source evidence and are not duplicated here.

-- Canonical source contracts. Duplicate headers in paket.xlsx are preserved by
-- the frontend source parser as deterministic __2 aliases.
do $$
begin
  perform public.register_system_source_contract(
    'PRODUCT_CONVERSION', '1', 'SAPUI5 dışa aktarımı',
    '["Üretim yeri","Bozulan/Birleştirilen Ürün Kodu","Miktar","Temel ölçü birimi","Oluşan Ürün Kodu","Miktar__2","Temel ölçü birimi__2"]'::jsonb,
    '["Üretim yeri","Bozulan/Birleştirilen Ürün Kodu","Miktar","Temel ölçü birimi","Oluşan Ürün Kodu","Miktar__2","Temel ölçü birimi__2"]'::jsonb,
    '{}'::jsonb, '{}'::jsonb, 'FULL_REPLACE'::public.publication_mode
  );

  perform public.register_system_source_contract(
    'SELLOUT', '1', 'SAPUI5 dışa aktarımı',
    '["Bayi/Distribütör","Malzeme Kodu","Malzeme Tnm.","Mal Grubu Tnm.","Miktar","Litre","Faturalama Tarihi"]'::jsonb,
    '["Bayi/Distribütör","Malzeme Kodu","Miktar","Litre"]'::jsonb,
    '{}'::jsonb, '{}'::jsonb, 'FULL_REPLACE'::public.publication_mode
  );

  perform public.register_system_source_contract(
    'KA_DELIVERY', '1', 'SAPUI5 dışa aktarımı',
    '["Bayi/Dist Kodu","Ürün Kodu","Malzeme kısa metni","Litre","Miktar","Yükleme Tarihi"]'::jsonb,
    '["Bayi/Dist Kodu","Ürün Kodu","Litre","Miktar"]'::jsonb,
    '{}'::jsonb, '{}'::jsonb, 'FULL_REPLACE'::public.publication_mode
  );
end;
$$;

create table public.product_domain_runs (
  id uuid primary key default gen_random_uuid(),
  scope_key text not null check (length(btrim(scope_key)) > 0),
  conversion_batch_id uuid not null references public.import_batches(id),
  sellout_batch_id uuid not null references public.import_batches(id),
  ka_batch_id uuid not null references public.import_batches(id),
  conversion_publication_id uuid not null references public.publications(id),
  sellout_publication_id uuid not null references public.publications(id),
  ka_publication_id uuid not null references public.publications(id),
  status text not null default 'CREATED' check (status in ('CREATED','RESOLVED')),
  summary jsonb not null default '{}'::jsonb check (jsonb_typeof(summary) = 'object'),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  resolved_at timestamptz,
  unique (scope_key, conversion_publication_id, sellout_publication_id, ka_publication_id)
);

create table public.product_domain_heads (
  scope_key text primary key check (length(btrim(scope_key)) > 0),
  active_run_id uuid not null references public.product_domain_runs(id),
  updated_at timestamptz not null default now()
);

create table public.product_conversion_edges (
  run_id uuid not null references public.product_domain_runs(id) on delete cascade,
  source_product_code text not null check (source_product_code ~ '^[0-9]+$'),
  target_product_code text not null check (target_product_code ~ '^[0-9]+$'),
  source_quantity_basis numeric not null check (source_quantity_basis > 0),
  target_quantity_basis numeric not null check (target_quantity_basis > 0),
  output_per_source numeric not null check (output_per_source > 0),
  source_uoms text[] not null default array[]::text[],
  target_uoms text[] not null default array[]::text[],
  observation_count bigint not null check (observation_count > 0),
  source_row_nos jsonb not null default '[]'::jsonb check (jsonb_typeof(source_row_nos) = 'array'),
  primary key (run_id, source_product_code, target_product_code),
  check (source_product_code <> target_product_code)
);

create table public.product_families (
  id uuid primary key default gen_random_uuid(),
  scope_key text not null check (length(btrim(scope_key)) > 0),
  normalized_name text not null check (length(btrim(normalized_name)) > 0),
  display_name text not null check (length(btrim(display_name)) > 0),
  raw_names jsonb not null default '[]'::jsonb check (jsonb_typeof(raw_names) = 'array'),
  updated_at timestamptz not null default now(),
  unique (scope_key, normalized_name)
);

create table public.product_variant_resolutions (
  run_id uuid not null references public.product_domain_runs(id) on delete cascade,
  scope_key text not null check (length(btrim(scope_key)) > 0),
  product_code text not null check (product_code ~ '^[0-9]+$'),
  product_name text,
  product_name_resolution_state text not null check (product_name_resolution_state in ('RESOLVED','PARTIAL','BLOCKED')),
  family_id uuid references public.product_families(id),
  family_resolution_state text not null check (family_resolution_state in ('RESOLVED','PARTIAL','BLOCKED')),
  family_source text check (family_source is null or family_source in ('SELLOUT','CONVERSION_GRAPH','APPROVED_MANUAL')),
  quantity_uom text,
  quantity_uom_resolution_state text not null check (quantity_uom_resolution_state in ('RESOLVED','PARTIAL','BLOCKED')),
  quantity_uom_source text check (quantity_uom_source is null or quantity_uom_source in ('PRODUCT_CONVERSION','APPROVED_MANUAL')),
  units_per_case numeric check (units_per_case is null or units_per_case > 0),
  unit_volume_ml numeric check (unit_volume_ml is null or unit_volume_ml > 0),
  canonical_stock_variant_code text check (canonical_stock_variant_code is null or canonical_stock_variant_code ~ '^[0-9]+$'),
  replenishment_variant_code text check (replenishment_variant_code is null or replenishment_variant_code ~ '^[0-9]+$'),
  volume_tracked boolean,
  sellout_lpu_candidate numeric check (sellout_lpu_candidate is null or sellout_lpu_candidate > 0),
  ka_lpu_candidate numeric check (ka_lpu_candidate is null or ka_lpu_candidate > 0),
  package_lpu_candidate numeric check (package_lpu_candidate is null or package_lpu_candidate > 0),
  lpu_numerator numeric check (lpu_numerator is null or lpu_numerator > 0),
  lpu_denominator numeric check (lpu_denominator is null or lpu_denominator > 0),
  lpu numeric generated always as (
    case when lpu_numerator is not null and lpu_denominator is not null then lpu_numerator / lpu_denominator end
  ) stored,
  lpu_resolution_state text not null check (lpu_resolution_state in ('RESOLVED','PARTIAL','BLOCKED')),
  lpu_source text check (lpu_source is null or lpu_source in ('SELLOUT','KA_DELIVERY','CONVERSION_GRAPH','APPROVED_MANUAL')),
  lpu_verification_state text not null check (lpu_verification_state in (
    'sellout_verified','ka_verified','cross_source_verified','unit_inconsistent',
    'derived_pending','manual_approved','non_volume','missing'
  )),
  lpu_source_variance numeric check (lpu_source_variance is null or lpu_source_variance >= 0),
  lpu_source_variance_ratio numeric check (lpu_source_variance_ratio is null or lpu_source_variance_ratio >= 0),
  conversion_delta_lpu numeric,
  conversion_component_key text,
  has_conversion boolean not null default false,
  resolution_evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(resolution_evidence) = 'object'),
  valid_from timestamptz not null default now(),
  valid_to timestamptz,
  resolved_at timestamptz not null default now(),
  primary key (run_id, product_code),
  check (valid_to is null or valid_to >= valid_from),
  check ((product_name_resolution_state = 'RESOLVED' and product_name is not null) or (product_name_resolution_state <> 'RESOLVED' and product_name is null)),
  check ((family_resolution_state = 'RESOLVED' and family_id is not null and family_source is not null) or (family_resolution_state <> 'RESOLVED' and family_id is null and family_source is null)),
  check ((quantity_uom_resolution_state = 'RESOLVED' and quantity_uom is not null and quantity_uom_source is not null) or (quantity_uom_resolution_state <> 'RESOLVED' and quantity_uom is null and quantity_uom_source is null)),
  check (
    (lpu_resolution_state = 'RESOLVED' and lpu_numerator is not null and lpu_denominator is not null and lpu_source is not null
      and lpu_verification_state in ('sellout_verified','ka_verified','cross_source_verified','derived_pending','manual_approved'))
    or
    (lpu_resolution_state = 'PARTIAL' and lpu_numerator is null and lpu_denominator is null and lpu_source is null
      and lpu_verification_state in ('missing','non_volume'))
    or
    (lpu_resolution_state = 'BLOCKED' and lpu_numerator is null and lpu_denominator is null
      and lpu_verification_state = 'unit_inconsistent')
  ),
  check (volume_tracked is distinct from false or (lpu is null and lpu_verification_state = 'non_volume'))
);

create table public.product_variants (
  scope_key text not null check (length(btrim(scope_key)) > 0),
  product_code text not null check (product_code ~ '^[0-9]+$'),
  product_name text,
  product_name_resolution_state text not null check (product_name_resolution_state in ('RESOLVED','PARTIAL','BLOCKED')),
  family_id uuid references public.product_families(id),
  family_resolution_state text not null check (family_resolution_state in ('RESOLVED','PARTIAL','BLOCKED')),
  family_source text check (family_source is null or family_source in ('SELLOUT','CONVERSION_GRAPH','APPROVED_MANUAL')),
  quantity_uom text,
  quantity_uom_resolution_state text not null check (quantity_uom_resolution_state in ('RESOLVED','PARTIAL','BLOCKED')),
  quantity_uom_source text check (quantity_uom_source is null or quantity_uom_source in ('PRODUCT_CONVERSION','APPROVED_MANUAL')),
  units_per_case numeric check (units_per_case is null or units_per_case > 0),
  unit_volume_ml numeric check (unit_volume_ml is null or unit_volume_ml > 0),
  canonical_stock_variant_code text check (canonical_stock_variant_code is null or canonical_stock_variant_code ~ '^[0-9]+$'),
  replenishment_variant_code text check (replenishment_variant_code is null or replenishment_variant_code ~ '^[0-9]+$'),
  volume_tracked boolean,
  sellout_lpu_candidate numeric check (sellout_lpu_candidate is null or sellout_lpu_candidate > 0),
  ka_lpu_candidate numeric check (ka_lpu_candidate is null or ka_lpu_candidate > 0),
  package_lpu_candidate numeric check (package_lpu_candidate is null or package_lpu_candidate > 0),
  lpu_numerator numeric check (lpu_numerator is null or lpu_numerator > 0),
  lpu_denominator numeric check (lpu_denominator is null or lpu_denominator > 0),
  lpu numeric generated always as (
    case when lpu_numerator is not null and lpu_denominator is not null then lpu_numerator / lpu_denominator end
  ) stored,
  lpu_resolution_state text not null check (lpu_resolution_state in ('RESOLVED','PARTIAL','BLOCKED')),
  lpu_source text check (lpu_source is null or lpu_source in ('SELLOUT','KA_DELIVERY','CONVERSION_GRAPH','APPROVED_MANUAL')),
  lpu_verification_state text not null check (lpu_verification_state in (
    'sellout_verified','ka_verified','cross_source_verified','unit_inconsistent',
    'derived_pending','manual_approved','non_volume','missing'
  )),
  lpu_source_variance numeric check (lpu_source_variance is null or lpu_source_variance >= 0),
  lpu_source_variance_ratio numeric check (lpu_source_variance_ratio is null or lpu_source_variance_ratio >= 0),
  conversion_delta_lpu numeric,
  conversion_component_key text,
  has_conversion boolean not null default false,
  current_source_state text not null check (current_source_state in ('PRESENT','NOT_PRESENT')),
  active_run_id uuid not null references public.product_domain_runs(id),
  current_resolution jsonb not null default '{}'::jsonb check (jsonb_typeof(current_resolution) = 'object'),
  updated_at timestamptz not null default now(),
  primary key (scope_key, product_code),
  check ((product_name_resolution_state = 'RESOLVED' and product_name is not null) or (product_name_resolution_state <> 'RESOLVED' and product_name is null)),
  check ((family_resolution_state = 'RESOLVED' and family_id is not null and family_source is not null) or (family_resolution_state <> 'RESOLVED' and family_id is null and family_source is null)),
  check ((quantity_uom_resolution_state = 'RESOLVED' and quantity_uom is not null and quantity_uom_source is not null) or (quantity_uom_resolution_state <> 'RESOLVED' and quantity_uom is null and quantity_uom_source is null)),
  check (
    (lpu_resolution_state = 'RESOLVED' and lpu_numerator is not null and lpu_denominator is not null and lpu_source is not null
      and lpu_verification_state in ('sellout_verified','ka_verified','cross_source_verified','derived_pending','manual_approved'))
    or
    (lpu_resolution_state = 'PARTIAL' and lpu_numerator is null and lpu_denominator is null and lpu_source is null
      and lpu_verification_state in ('missing','non_volume'))
    or
    (lpu_resolution_state = 'BLOCKED' and lpu_numerator is null and lpu_denominator is null
      and lpu_verification_state = 'unit_inconsistent')
  ),
  check (volume_tracked is distinct from false or (lpu is null and lpu_verification_state = 'non_volume'))
);

create index product_conversion_edges_component_idx
  on public.product_conversion_edges(run_id, source_product_code, target_product_code);
create index product_variant_resolutions_run_state_idx
  on public.product_variant_resolutions(run_id, family_resolution_state, lpu_resolution_state, product_code);
create index product_variant_resolutions_validity_idx
  on public.product_variant_resolutions(scope_key, product_code, valid_from, valid_to);
create index product_variants_current_idx
  on public.product_variants(scope_key, current_source_state, product_code);

alter table public.product_domain_runs enable row level security;
alter table public.product_domain_heads enable row level security;
alter table public.product_conversion_edges enable row level security;
alter table public.product_families enable row level security;
alter table public.product_variant_resolutions enable row level security;
alter table public.product_variants enable row level security;

create policy product_domain_runs_admin_read on public.product_domain_runs for select to authenticated using (public.is_admin());
create policy product_domain_heads_admin_read on public.product_domain_heads for select to authenticated using (public.is_admin());
create policy product_conversion_edges_admin_read on public.product_conversion_edges for select to authenticated using (public.is_admin());
create policy product_families_admin_read on public.product_families for select to authenticated using (public.is_admin());
create policy product_variant_resolutions_admin_read on public.product_variant_resolutions for select to authenticated using (public.is_admin());
create policy product_variants_admin_read on public.product_variants for select to authenticated using (public.is_admin());

grant select on public.product_domain_runs, public.product_domain_heads, public.product_conversion_edges,
  public.product_families, public.product_variant_resolutions, public.product_variants to authenticated;

create or replace function public.product_family_key(p_value text)
returns text
language sql
immutable
strict
set search_path = pg_catalog, public
as $$
  select lower(regexp_replace(btrim(p_value), '\s+', ' ', 'g'));
$$;

-- Compact per-product evidence aggregation over Package 01 staging. No raw row
-- copy is created in Package 03.
create or replace function public.product_lpu_evidence_aggregate(p_batch_id uuid, p_source_kind text)
returns table (
  product_code text,
  row_count bigint,
  positive_row_count bigint,
  return_row_count bigint,
  invalid_numeric_row_count bigint,
  non_candidate_row_count bigint,
  positive_quantity_sum numeric,
  positive_litres_sum numeric,
  aggregate_lpu numeric,
  row_lpu_distinct_count bigint,
  row_lpu_min numeric,
  row_lpu_max numeric,
  row_lpu_spread numeric,
  row_lpu_spread_ratio numeric,
  product_name_candidate_count bigint,
  stable_product_name text,
  family_candidate_count bigint,
  stable_family_key text,
  stable_family_name text,
  source_row_min bigint,
  source_row_max bigint
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with source_rows as (
    select
      s.source_row_no,
      case p_source_kind
        when 'SELLOUT' then btrim(s.payload ->> 'Malzeme Kodu')
        when 'KA_DELIVERY' then btrim(s.payload ->> 'Ürün Kodu')
      end as product_code,
      nullif(btrim(case p_source_kind
        when 'SELLOUT' then s.payload ->> 'Malzeme Tnm.'
        when 'KA_DELIVERY' then s.payload ->> 'Malzeme kısa metni'
      end), '') as product_name,
      case when p_source_kind = 'SELLOUT' then nullif(btrim(s.payload ->> 'Mal Grubu Tnm.'), '') end as raw_family,
      s.payload ->> 'Miktar' as quantity_text,
      s.payload ->> 'Litre' as litres_text
    from public.staging_rows s
    where s.batch_id = p_batch_id
      and s.row_status = 'VALID'
  ), parsed as (
    select
      source_row_no,
      product_code,
      product_name,
      raw_family,
      case when coalesce(quantity_text, '') ~ '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$' then quantity_text::numeric end as quantity,
      case when coalesce(litres_text, '') ~ '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$' then litres_text::numeric end as litres
    from source_rows
    where product_code ~ '^[0-9]+$'
  ), evaluated as (
    select
      *,
      (quantity is not null and litres is not null and quantity > 0 and litres > 0) as is_positive_candidate,
      (quantity is not null and litres is not null and quantity < 0 and litres < 0) as is_return_row,
      case when quantity is not null and litres is not null and quantity > 0 and litres > 0
        then litres / quantity end as row_lpu
    from parsed
  ), grouped as (
    select
      product_code,
      count(*)::bigint as row_count,
      count(*) filter (where is_positive_candidate)::bigint as positive_row_count,
      count(*) filter (where is_return_row)::bigint as return_row_count,
      count(*) filter (where quantity is null or litres is null)::bigint as invalid_numeric_row_count,
      count(*) filter (where not is_positive_candidate)::bigint as non_candidate_row_count,
      sum(quantity) filter (where is_positive_candidate) as positive_quantity_sum,
      sum(litres) filter (where is_positive_candidate) as positive_litres_sum,
      count(distinct row_lpu) filter (where row_lpu is not null)::bigint as row_lpu_distinct_count,
      min(row_lpu) filter (where row_lpu is not null) as row_lpu_min,
      max(row_lpu) filter (where row_lpu is not null) as row_lpu_max,
      count(distinct product_name) filter (where product_name is not null)::bigint as product_name_candidate_count,
      min(product_name collate "C") filter (where product_name is not null) as stable_product_name_candidate,
      count(distinct public.product_family_key(raw_family)) filter (where raw_family is not null)::bigint as family_candidate_count,
      min(public.product_family_key(raw_family) collate "C") filter (where raw_family is not null) as stable_family_key_candidate,
      min(raw_family collate "C") filter (where raw_family is not null) as stable_family_name_candidate,
      min(source_row_no)::bigint as source_row_min,
      max(source_row_no)::bigint as source_row_max
    from evaluated
    group by product_code
  )
  select
    product_code,
    row_count,
    positive_row_count,
    return_row_count,
    invalid_numeric_row_count,
    non_candidate_row_count,
    positive_quantity_sum,
    positive_litres_sum,
    case when positive_quantity_sum > 0 and positive_litres_sum > 0 then positive_litres_sum / positive_quantity_sum end,
    row_lpu_distinct_count,
    row_lpu_min,
    row_lpu_max,
    case when row_lpu_min is not null and row_lpu_max is not null then row_lpu_max - row_lpu_min end,
    case
      when positive_quantity_sum > 0 and positive_litres_sum > 0 and row_lpu_min is not null and row_lpu_max is not null
      then (row_lpu_max - row_lpu_min) / (positive_litres_sum / positive_quantity_sum)
    end,
    product_name_candidate_count,
    case when product_name_candidate_count = 1 then stable_product_name_candidate end,
    family_candidate_count,
    case when family_candidate_count = 1 then stable_family_key_candidate end,
    case when family_candidate_count = 1 then stable_family_name_candidate end,
    source_row_min,
    source_row_max
  from grouped;
$$;

create or replace function public.assert_current_product_source_batch(
  p_batch_id uuid,
  p_expected_source_kind text,
  p_expected_contract_version text,
  p_scope_key text
) returns uuid
language plpgsql
stable
security definer
set search_path = pg_catalog, public
as $$
declare
  v_publication_id uuid;
begin
  select b.published_publication_id
  into v_publication_id
  from public.import_batches b
  join public.source_contract_versions sc on sc.id = b.source_contract_version_id
  join public.validation_runs vr on vr.id = b.validation_run_id
  join public.import_reconciliations ir on ir.id = b.reconciliation_id
  join public.publications p on p.id = b.published_publication_id
  join public.candidate_publications cp on cp.id = p.candidate_id
  join public.publication_heads h
    on h.source_kind = b.source_kind
   and h.scope_key = b.scope_key
   and h.active_publication_id = p.id
  where b.id = p_batch_id
    and b.source_kind = p_expected_source_kind
    and b.scope_key = p_scope_key
    and sc.source_kind = b.source_kind
    and sc.version = p_expected_contract_version
    and b.source_verified_at is not null
    and b.status = 'PUBLISHED'
    and vr.batch_id = b.id
    and vr.contract_version_id = b.source_contract_version_id
    and vr.status = 'PASSED'
    and not exists (
      select 1 from public.validation_issues vi
      where vi.validation_run_id = vr.id and vi.severity = 'BLOCKING'
    )
    and ir.batch_id = b.id
    and ir.status = 'MATCHED'
    and cp.batch_id = b.id
    and cp.validation_run_id = vr.id
    and cp.reconciliation_id = ir.id
    and cp.status = 'PUBLISHED'
    and p.source_kind = b.source_kind
    and p.scope_key = b.scope_key
    and p.published_at is not null;

  if v_publication_id is null then
    raise exception '% v% batch must be the current source-verified, validated, reconciled and published Package 01 head for scope %', p_expected_source_kind, p_expected_contract_version, p_scope_key
      using errcode = '22023';
  end if;
  return v_publication_id;
end;
$$;

create or replace function public.materialize_current_product_domain(p_scope_key text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
set statement_timeout = '60s'
as $$
declare
  v_scope text := btrim(p_scope_key);
  v_conversion_batch uuid;
  v_sellout_batch uuid;
  v_ka_batch uuid;
  v_conversion_publication uuid;
  v_sellout_publication uuid;
  v_ka_publication uuid;
  v_run_id uuid;
  v_existing_summary jsonb;
  v_summary jsonb;
  v_edge_count bigint;
  v_conversion_observation_count bigint;
  v_conversion_product_count bigint;
  v_variant_count bigint;
  v_effective_at timestamptz := clock_timestamp();
begin
  perform public.assert_import_admin();
  if v_scope is null or v_scope = '' then
    raise exception 'Product domain scope is required' using errcode = '22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('product-domain:' || v_scope, 0));

  select cp.batch_id into v_conversion_batch
  from public.publication_heads h
  join public.publications p on p.id = h.active_publication_id
  join public.candidate_publications cp on cp.id = p.candidate_id
  where h.source_kind = 'PRODUCT_CONVERSION' and h.scope_key = v_scope;

  select cp.batch_id into v_sellout_batch
  from public.publication_heads h
  join public.publications p on p.id = h.active_publication_id
  join public.candidate_publications cp on cp.id = p.candidate_id
  where h.source_kind = 'SELLOUT' and h.scope_key = v_scope;

  select cp.batch_id into v_ka_batch
  from public.publication_heads h
  join public.publications p on p.id = h.active_publication_id
  join public.candidate_publications cp on cp.id = p.candidate_id
  where h.source_kind = 'KA_DELIVERY' and h.scope_key = v_scope;

  if v_conversion_batch is null or v_sellout_batch is null or v_ka_batch is null then
    raise exception 'Current PRODUCT_CONVERSION, SELLOUT and KA_DELIVERY publications are all required for scope %', v_scope
      using errcode = '55000';
  end if;

  v_conversion_publication := public.assert_current_product_source_batch(v_conversion_batch, 'PRODUCT_CONVERSION', '1', v_scope);
  v_sellout_publication := public.assert_current_product_source_batch(v_sellout_batch, 'SELLOUT', '1', v_scope);
  v_ka_publication := public.assert_current_product_source_batch(v_ka_batch, 'KA_DELIVERY', '1', v_scope);

  if exists (
    select 1 from public.staging_rows s
    where s.batch_id = v_conversion_batch and s.row_status = 'VALID'
      and btrim(s.payload ->> 'Üretim yeri') is distinct from v_scope
  ) then
    raise exception 'PRODUCT_CONVERSION embedded scope does not match declared scope %', v_scope using errcode = '22023';
  end if;
  if exists (
    select 1 from public.staging_rows s
    where s.batch_id = v_sellout_batch and s.row_status = 'VALID'
      and btrim(s.payload ->> 'Bayi/Distribütör') is distinct from v_scope
  ) then
    raise exception 'SELLOUT embedded scope does not match declared scope %', v_scope using errcode = '22023';
  end if;
  if exists (
    select 1 from public.staging_rows s
    where s.batch_id = v_ka_batch and s.row_status = 'VALID'
      and btrim(s.payload ->> 'Bayi/Dist Kodu') is distinct from v_scope
  ) then
    raise exception 'KA_DELIVERY embedded scope does not match declared scope %', v_scope using errcode = '22023';
  end if;

  select id, summary into v_run_id, v_existing_summary
  from public.product_domain_runs
  where scope_key = v_scope
    and conversion_publication_id = v_conversion_publication
    and sellout_publication_id = v_sellout_publication
    and ka_publication_id = v_ka_publication;

  if v_run_id is not null and exists (select 1 from public.product_domain_runs where id = v_run_id and status = 'RESOLVED') then
    return jsonb_build_object('run_id', v_run_id, 'reused', true, 'summary', v_existing_summary);
  end if;

  if v_run_id is null then
    insert into public.product_domain_runs(
      scope_key, conversion_batch_id, sellout_batch_id, ka_batch_id,
      conversion_publication_id, sellout_publication_id, ka_publication_id, created_by
    ) values (
      v_scope, v_conversion_batch, v_sellout_batch, v_ka_batch,
      v_conversion_publication, v_sellout_publication, v_ka_publication, auth.uid()
    ) returning id into v_run_id;
  end if;

  if exists (
    select 1
    from public.staging_rows s
    where s.batch_id = v_conversion_batch
      and s.row_status = 'VALID'
      and (
        coalesce(btrim(s.payload ->> 'Bozulan/Birleştirilen Ürün Kodu'), '') !~ '^[0-9]+$'
        or coalesce(btrim(s.payload ->> 'Oluşan Ürün Kodu'), '') !~ '^[0-9]+$'
        or coalesce(s.payload ->> 'Miktar', '') !~ '^(0|[1-9][0-9]*)(\.[0-9]+)?$'
        or coalesce(s.payload ->> 'Miktar__2', '') !~ '^(0|[1-9][0-9]*)(\.[0-9]+)?$'
      )
  ) then
    raise exception 'PRODUCT_CONVERSION contains an invalid product code or non-numeric conversion quantity' using errcode = '22023';
  end if;

  if exists (
    select 1
    from public.staging_rows s
    where s.batch_id = v_conversion_batch
      and s.row_status = 'VALID'
      and ((s.payload ->> 'Miktar')::numeric <= 0 or (s.payload ->> 'Miktar__2')::numeric <= 0)
  ) then
    raise exception 'PRODUCT_CONVERSION contains a non-positive conversion quantity' using errcode = '22023';
  end if;

  if exists (
    select 1 from public.staging_rows s
    where s.batch_id = v_conversion_batch
      and s.row_status = 'VALID'
      and btrim(s.payload ->> 'Bozulan/Birleştirilen Ürün Kodu') in ('154558','154559')
      and btrim(s.payload ->> 'Oluşan Ürün Kodu') = '150003'
  ) then
    raise exception 'Rejected conversion mapping 154558/154559 -> 150003 is not allowed' using errcode = '23514';
  end if;

  -- Exact rational comparison: repeated rows for one directed relation must
  -- describe the same conversion factor. No arbitrary decimal rounding is used.
  if exists (
    with observations as (
      select
        s.source_row_no,
        btrim(s.payload ->> 'Bozulan/Birleştirilen Ürün Kodu') as source_product_code,
        btrim(s.payload ->> 'Oluşan Ürün Kodu') as target_product_code,
        (s.payload ->> 'Miktar')::numeric as source_quantity,
        (s.payload ->> 'Miktar__2')::numeric as target_quantity
      from public.staging_rows s
      where s.batch_id = v_conversion_batch and s.row_status = 'VALID'
    )
    select 1
    from observations a
    join observations b
      on b.source_product_code = a.source_product_code
     and b.target_product_code = a.target_product_code
     and b.source_row_no > a.source_row_no
    where a.target_quantity * b.source_quantity <> b.target_quantity * a.source_quantity
  ) then
    raise exception 'PRODUCT_CONVERSION contains conflicting factors for the same directed product relation' using errcode = '23514';
  end if;

  delete from public.product_conversion_edges where run_id = v_run_id;

  insert into public.product_conversion_edges(
    run_id, source_product_code, target_product_code, source_quantity_basis, target_quantity_basis,
    output_per_source, source_uoms, target_uoms, observation_count, source_row_nos
  )
  with observations as (
    select
      s.source_row_no,
      btrim(s.payload ->> 'Bozulan/Birleştirilen Ürün Kodu') as source_product_code,
      btrim(s.payload ->> 'Oluşan Ürün Kodu') as target_product_code,
      (s.payload ->> 'Miktar')::numeric as source_quantity,
      (s.payload ->> 'Miktar__2')::numeric as target_quantity,
      nullif(btrim(s.payload ->> 'Temel ölçü birimi'), '') as source_uom,
      nullif(btrim(s.payload ->> 'Temel ölçü birimi__2'), '') as target_uom
    from public.staging_rows s
    where s.batch_id = v_conversion_batch and s.row_status = 'VALID'
  ), representative as (
    select distinct on (source_product_code, target_product_code)
      source_product_code, target_product_code, source_quantity, target_quantity
    from observations
    order by source_product_code, target_product_code, source_row_no
  ), grouped as (
    select
      source_product_code,
      target_product_code,
      coalesce(array_agg(distinct source_uom order by source_uom) filter (where source_uom is not null), array[]::text[]) as source_uoms,
      coalesce(array_agg(distinct target_uom order by target_uom) filter (where target_uom is not null), array[]::text[]) as target_uoms,
      count(*)::bigint as observation_count,
      jsonb_agg(source_row_no order by source_row_no) as source_row_nos
    from observations
    group by source_product_code, target_product_code
  )
  select
    v_run_id, g.source_product_code, g.target_product_code,
    r.source_quantity, r.target_quantity, r.target_quantity / r.source_quantity,
    g.source_uoms, g.target_uoms, g.observation_count, g.source_row_nos
  from grouped g
  join representative r using (source_product_code, target_product_code);

  -- The same product code cannot carry two physical quantity UOMs inside the
  -- conversion graph. Such a component would make package factors semantically ambiguous.
  if exists (
    with uom_candidates as (
      select e.source_product_code as product_code, u.uom
      from public.product_conversion_edges e cross join lateral unnest(e.source_uoms) as u(uom)
      where e.run_id = v_run_id
      union all
      select e.target_product_code, u.uom
      from public.product_conversion_edges e cross join lateral unnest(e.target_uoms) as u(uom)
      where e.run_id = v_run_id
    )
    select 1 from uom_candidates group by product_code having count(distinct uom) > 1
  ) then
    raise exception 'PRODUCT_CONVERSION contains conflicting quantity UOM evidence for a product code' using errcode = '23514';
  end if;

  select count(*), coalesce(sum(observation_count), 0) into v_edge_count, v_conversion_observation_count
  from public.product_conversion_edges where run_id = v_run_id;
  select count(distinct code) into v_conversion_product_count
  from (
    select source_product_code as code from public.product_conversion_edges where run_id = v_run_id
    union
    select target_product_code as code from public.product_conversion_edges where run_id = v_run_id
  ) q;

  -- Cycle/path consistency is checked as exact rational arithmetic using
  -- numerator/denominator products, not hidden rounding of decimal factors.
  if exists (
    with recursive
    nodes as (
      select source_product_code as product_code from public.product_conversion_edges where run_id = v_run_id
      union
      select target_product_code from public.product_conversion_edges where run_id = v_run_id
    ),
    edge_steps as (
      select source_product_code as source_code, target_product_code as target_code,
        source_quantity_basis as multiplier_num, target_quantity_basis as multiplier_den
      from public.product_conversion_edges where run_id = v_run_id
      union all
      select target_product_code, source_product_code,
        target_quantity_basis, source_quantity_basis
      from public.product_conversion_edges where run_id = v_run_id
    ),
    relative_walk(origin_code, product_code, relative_num, relative_den, path) as (
      select product_code, product_code, 1::numeric, 1::numeric, array[product_code]::text[] from nodes
      union all
      select
        w.origin_code,
        e.target_code,
        w.relative_num * e.multiplier_num,
        w.relative_den * e.multiplier_den,
        w.path || e.target_code
      from relative_walk w
      join edge_steps e on e.source_code = w.product_code
      where not e.target_code = any(w.path)
    )
    select 1
    from relative_walk a
    join relative_walk b
      on b.origin_code = a.origin_code
     and b.product_code = a.product_code
     and b.path::text > a.path::text
    where a.relative_num * b.relative_den <> b.relative_num * a.relative_den
  ) then
    raise exception 'PRODUCT_CONVERSION graph contains internally inconsistent factor paths' using errcode = '23514';
  end if;

  insert into public.product_families(scope_key, normalized_name, display_name, raw_names)
  select
    v_scope,
    family_key,
    min(family_name collate "C"),
    jsonb_agg(distinct family_name order by family_name)
  from (
    select stable_family_key as family_key, stable_family_name as family_name
    from public.product_lpu_evidence_aggregate(v_sellout_batch, 'SELLOUT')
    where family_candidate_count = 1 and stable_family_key is not null and stable_family_name is not null
  ) f
  group by family_key
  on conflict (scope_key, normalized_name) do update
    set display_name = excluded.display_name,
        raw_names = excluded.raw_names,
        updated_at = now();

  delete from public.product_variant_resolutions where run_id = v_run_id;

  insert into public.product_variant_resolutions(
    run_id, scope_key, product_code, product_name, product_name_resolution_state,
    family_id, family_resolution_state, family_source,
    quantity_uom, quantity_uom_resolution_state, quantity_uom_source,
    units_per_case, unit_volume_ml, canonical_stock_variant_code, replenishment_variant_code, volume_tracked,
    sellout_lpu_candidate, ka_lpu_candidate, package_lpu_candidate,
    lpu_numerator, lpu_denominator, lpu_resolution_state, lpu_source, lpu_verification_state,
    lpu_source_variance, lpu_source_variance_ratio, conversion_delta_lpu,
    conversion_component_key, has_conversion, resolution_evidence, valid_from
  )
  with recursive
  sellout as materialized (
    select * from public.product_lpu_evidence_aggregate(v_sellout_batch, 'SELLOUT')
  ),
  ka as materialized (
    select * from public.product_lpu_evidence_aggregate(v_ka_batch, 'KA_DELIVERY')
  ),
  nodes as (
    select source_product_code as product_code from public.product_conversion_edges where run_id = v_run_id
    union
    select target_product_code from public.product_conversion_edges where run_id = v_run_id
  ),
  edge_steps as (
    select source_product_code as source_code, target_product_code as target_code,
      source_quantity_basis as multiplier_num, target_quantity_basis as multiplier_den
    from public.product_conversion_edges where run_id = v_run_id
    union all
    select target_product_code, source_product_code,
      target_quantity_basis, source_quantity_basis
    from public.product_conversion_edges where run_id = v_run_id
  ),
  connectivity(origin_code, product_code, path) as (
    select product_code, product_code, array[product_code]::text[] from nodes
    union all
    select c.origin_code, e.target_code, c.path || e.target_code
    from connectivity c
    join edge_steps e on e.source_code = c.product_code
    where not e.target_code = any(c.path)
  ),
  component_map as (
    select product_code, min(origin_code collate "C") as component_key
    from connectivity
    group by product_code
  ),
  uom_evidence as (
    select product_code, count(distinct uom)::bigint as uom_candidate_count, min(uom collate "C") as stable_uom
    from (
      select e.source_product_code as product_code, u.uom
      from public.product_conversion_edges e cross join lateral unnest(e.source_uoms) as u(uom)
      where e.run_id = v_run_id
      union all
      select e.target_product_code, u.uom
      from public.product_conversion_edges e cross join lateral unnest(e.target_uoms) as u(uom)
      where e.run_id = v_run_id
    ) q
    group by product_code
  ),
  all_products as (
    select product_code from nodes
    union select product_code from sellout
    union select product_code from ka
  ),
  direct_lpu as (
    select
      p.product_code,
      case
        when coalesce(s.positive_row_count, 0) > 0 then s.positive_litres_sum
        when coalesce(k.positive_row_count, 0) > 0 then k.positive_litres_sum
      end as lpu_num,
      case
        when coalesce(s.positive_row_count, 0) > 0 then s.positive_quantity_sum
        when coalesce(k.positive_row_count, 0) > 0 then k.positive_quantity_sum
      end as lpu_den,
      case
        when coalesce(s.positive_row_count, 0) > 0 then 'RESOLVED'
        when coalesce(k.positive_row_count, 0) > 0 then 'RESOLVED'
        else 'NONE'
      end as direct_state,
      case
        when coalesce(s.positive_row_count, 0) > 0 then 'SELLOUT'
        when coalesce(k.positive_row_count, 0) > 0 then 'KA_DELIVERY'
      end as direct_source
    from all_products p
    left join sellout s using (product_code)
    left join ka k using (product_code)
  ),
  graph_walk(anchor_code, product_code, candidate_num, candidate_den, path) as (
    select d.product_code, d.product_code, d.lpu_num, d.lpu_den, array[d.product_code]::text[]
    from direct_lpu d
    join nodes n using (product_code)
    where d.direct_state = 'RESOLVED' and d.lpu_num > 0 and d.lpu_den > 0
    union all
    select
      w.anchor_code,
      e.target_code,
      w.candidate_num * e.multiplier_num,
      w.candidate_den * e.multiplier_den,
      w.path || e.target_code
    from graph_walk w
    join edge_steps e on e.source_code = w.product_code
    where not e.target_code = any(w.path)
  ),
  graph_conflicts as (
    select distinct a.product_code
    from graph_walk a
    join graph_walk b
      on b.product_code = a.product_code
     and b.anchor_code > a.anchor_code
    where a.candidate_num * b.candidate_den <> b.candidate_num * a.candidate_den
  ),
  graph_choice as (
    select distinct on (product_code)
      product_code, anchor_code, candidate_num, candidate_den
    from graph_walk
    order by product_code, anchor_code
  ),
  graph_lpu as (
    select
      g.product_code,
      g.candidate_num,
      g.candidate_den,
      count(distinct w.anchor_code)::bigint as anchor_count,
      (c.product_code is not null) as has_conflict,
      jsonb_agg(
        jsonb_build_object(
          'anchor', w.anchor_code,
          'numerator', w.candidate_num::text,
          'denominator', w.candidate_den::text,
          'lpu', (w.candidate_num / w.candidate_den)::text
        ) order by w.anchor_code
      ) as candidates
    from graph_choice g
    join graph_walk w using (product_code)
    left join graph_conflicts c using (product_code)
    group by g.product_code, g.candidate_num, g.candidate_den, c.product_code
  ),
  component_family as (
    select
      cm.component_key,
      count(distinct s.stable_family_key)::bigint as family_candidate_count,
      min(s.stable_family_key collate "C") as stable_family_key,
      count(distinct s.product_code)::bigint as direct_family_product_count
    from component_map cm
    join sellout s on s.product_code = cm.product_code
    where s.family_candidate_count = 1 and s.stable_family_key is not null
    group by cm.component_key
  ),
  chosen as (
    select
      p.product_code,
      cm.component_key,
      (cm.product_code is not null) as has_conversion,
      ue.uom_candidate_count,
      ue.stable_uom,
      s.row_count as sellout_row_count,
      s.positive_row_count as sellout_positive_row_count,
      s.return_row_count as sellout_return_row_count,
      s.invalid_numeric_row_count as sellout_invalid_numeric_row_count,
      s.non_candidate_row_count as sellout_non_candidate_row_count,
      s.positive_quantity_sum as sellout_positive_quantity_sum,
      s.positive_litres_sum as sellout_positive_litres_sum,
      s.aggregate_lpu as sellout_lpu_candidate,
      s.row_lpu_distinct_count as sellout_row_lpu_distinct_count,
      s.row_lpu_min as sellout_row_lpu_min,
      s.row_lpu_max as sellout_row_lpu_max,
      s.row_lpu_spread as sellout_row_lpu_spread,
      s.row_lpu_spread_ratio as sellout_row_lpu_spread_ratio,
      s.product_name_candidate_count as sellout_name_candidate_count,
      s.stable_product_name as sellout_name,
      s.family_candidate_count as sellout_family_candidate_count,
      s.stable_family_key as sellout_family_key,
      s.stable_family_name as sellout_family_name,
      k.row_count as ka_row_count,
      k.positive_row_count as ka_positive_row_count,
      k.return_row_count as ka_return_row_count,
      k.invalid_numeric_row_count as ka_invalid_numeric_row_count,
      k.non_candidate_row_count as ka_non_candidate_row_count,
      k.positive_quantity_sum as ka_positive_quantity_sum,
      k.positive_litres_sum as ka_positive_litres_sum,
      k.aggregate_lpu as ka_lpu_candidate,
      k.row_lpu_distinct_count as ka_row_lpu_distinct_count,
      k.row_lpu_min as ka_row_lpu_min,
      k.row_lpu_max as ka_row_lpu_max,
      k.row_lpu_spread as ka_row_lpu_spread,
      k.row_lpu_spread_ratio as ka_row_lpu_spread_ratio,
      k.product_name_candidate_count as ka_name_candidate_count,
      k.stable_product_name as ka_name,
      d.lpu_num as direct_lpu_num,
      d.lpu_den as direct_lpu_den,
      d.direct_state,
      d.direct_source,
      gl.candidate_num as graph_lpu_num,
      gl.candidate_den as graph_lpu_den,
      gl.anchor_count as graph_anchor_count,
      gl.has_conflict as graph_has_conflict,
      gl.candidates as graph_candidates,
      cf.family_candidate_count as component_family_candidate_count,
      cf.stable_family_key as component_family_key,
      cf.direct_family_product_count
    from all_products p
    left join sellout s using (product_code)
    left join ka k using (product_code)
    left join direct_lpu d using (product_code)
    left join component_map cm using (product_code)
    left join uom_evidence ue using (product_code)
    left join graph_lpu gl using (product_code)
    left join component_family cf on cf.component_key = cm.component_key
  ),
  final as (
    select
      c.*,
      case
        when coalesce(c.sellout_name_candidate_count, 0) = 1 then c.sellout_name
        when coalesce(c.sellout_name_candidate_count, 0) > 1 then null
        when coalesce(c.ka_name_candidate_count, 0) = 1 then c.ka_name
        else null
      end as product_name,
      case
        when coalesce(c.sellout_name_candidate_count, 0) = 1 then 'RESOLVED'
        when coalesce(c.sellout_name_candidate_count, 0) > 1 then 'BLOCKED'
        when coalesce(c.ka_name_candidate_count, 0) = 1 then 'RESOLVED'
        when coalesce(c.ka_name_candidate_count, 0) > 1 then 'BLOCKED'
        else 'PARTIAL'
      end as product_name_state,
      case
        when coalesce(c.sellout_family_candidate_count, 0) = 1 then c.sellout_family_key
        when coalesce(c.sellout_family_candidate_count, 0) > 1 then null
        when coalesce(c.component_family_candidate_count, 0) = 1 then c.component_family_key
        else null
      end as final_family_key,
      case
        when coalesce(c.sellout_family_candidate_count, 0) = 1 then 'RESOLVED'
        when coalesce(c.sellout_family_candidate_count, 0) > 1 then 'BLOCKED'
        when coalesce(c.component_family_candidate_count, 0) = 1 then 'RESOLVED'
        when coalesce(c.component_family_candidate_count, 0) > 1 then 'BLOCKED'
        else 'PARTIAL'
      end as family_state,
      case
        when coalesce(c.sellout_family_candidate_count, 0) = 1 then 'SELLOUT'
        when coalesce(c.sellout_family_candidate_count, 0) = 0 and coalesce(c.component_family_candidate_count, 0) = 1 then 'CONVERSION_GRAPH'
      end as family_source,
      case when coalesce(c.uom_candidate_count, 0) = 1 then c.stable_uom end as final_quantity_uom,
      case when coalesce(c.uom_candidate_count, 0) = 1 then 'RESOLVED' else 'PARTIAL' end as quantity_uom_state,
      case when coalesce(c.uom_candidate_count, 0) = 1 then 'PRODUCT_CONVERSION' end as quantity_uom_source,
      case
        when c.direct_state = 'RESOLVED' then c.direct_lpu_num
        when coalesce(c.graph_has_conflict, false) then null
        when c.graph_lpu_num is not null then c.graph_lpu_num
      end as final_lpu_num,
      case
        when c.direct_state = 'RESOLVED' then c.direct_lpu_den
        when coalesce(c.graph_has_conflict, false) then null
        when c.graph_lpu_den is not null then c.graph_lpu_den
      end as final_lpu_den,
      case
        when c.direct_state = 'RESOLVED' then 'RESOLVED'
        when coalesce(c.graph_has_conflict, false) then 'BLOCKED'
        when c.graph_lpu_num is not null and c.graph_lpu_den is not null then 'RESOLVED'
        else 'PARTIAL'
      end as lpu_state,
      case
        when c.direct_state = 'RESOLVED' then c.direct_source
        when not coalesce(c.graph_has_conflict, false) and c.graph_lpu_num is not null then 'CONVERSION_GRAPH'
      end as final_lpu_source,
      case
        when c.direct_state = 'RESOLVED' and c.direct_source = 'SELLOUT'
          and coalesce(c.sellout_positive_row_count, 0) > 0 and coalesce(c.ka_positive_row_count, 0) > 0
          and c.sellout_positive_litres_sum * c.ka_positive_quantity_sum = c.ka_positive_litres_sum * c.sellout_positive_quantity_sum
          then 'cross_source_verified'
        when c.direct_state = 'RESOLVED' and c.direct_source = 'SELLOUT' then 'sellout_verified'
        when c.direct_state = 'RESOLVED' and c.direct_source = 'KA_DELIVERY' then 'ka_verified'
        when coalesce(c.graph_has_conflict, false) then 'unit_inconsistent'
        when c.graph_lpu_num is not null and c.graph_lpu_den is not null then 'derived_pending'
        else 'missing'
      end as lpu_verification_state,
      case
        when coalesce(c.sellout_positive_row_count, 0) > 0 and coalesce(c.ka_positive_row_count, 0) > 0
        then abs(c.sellout_lpu_candidate - c.ka_lpu_candidate)
      end as lpu_source_variance,
      case
        when coalesce(c.sellout_positive_row_count, 0) > 0 and coalesce(c.ka_positive_row_count, 0) > 0 and c.sellout_lpu_candidate > 0
        then abs(c.sellout_lpu_candidate - c.ka_lpu_candidate) / c.sellout_lpu_candidate
      end as lpu_source_variance_ratio,
      case
        when c.direct_state = 'RESOLVED' and not coalesce(c.graph_has_conflict, false)
          and c.graph_lpu_num is not null and c.graph_lpu_den is not null
        then (c.direct_lpu_num / c.direct_lpu_den) - (c.graph_lpu_num / c.graph_lpu_den)
      end as conversion_delta_lpu
    from chosen c
  )
  select
    v_run_id,
    v_scope,
    f.product_code,
    f.product_name,
    f.product_name_state,
    pf.id,
    f.family_state,
    f.family_source,
    f.final_quantity_uom,
    f.quantity_uom_state,
    f.quantity_uom_source,
    null::numeric as units_per_case,
    null::numeric as unit_volume_ml,
    null::text as canonical_stock_variant_code,
    null::text as replenishment_variant_code,
    case when f.lpu_state = 'RESOLVED' then true else null end as volume_tracked,
    f.sellout_lpu_candidate,
    f.ka_lpu_candidate,
    case when not coalesce(f.graph_has_conflict, false) and f.graph_lpu_num is not null and f.graph_lpu_den is not null then f.graph_lpu_num / f.graph_lpu_den end,
    f.final_lpu_num,
    f.final_lpu_den,
    f.lpu_state,
    f.final_lpu_source,
    f.lpu_verification_state,
    f.lpu_source_variance,
    f.lpu_source_variance_ratio,
    f.conversion_delta_lpu,
    f.component_key,
    f.has_conversion,
    jsonb_build_object(
      'source_publications', jsonb_build_object(
        'PRODUCT_CONVERSION', v_conversion_publication,
        'SELLOUT', v_sellout_publication,
        'KA_DELIVERY', v_ka_publication
      ),
      'source_batches', jsonb_build_object(
        'PRODUCT_CONVERSION', v_conversion_batch,
        'SELLOUT', v_sellout_batch,
        'KA_DELIVERY', v_ka_batch
      ),
      'sellout', jsonb_build_object(
        'rows', coalesce(f.sellout_row_count, 0),
        'positive_rows', coalesce(f.sellout_positive_row_count, 0),
        'return_rows', coalesce(f.sellout_return_row_count, 0),
        'invalid_numeric_rows', coalesce(f.sellout_invalid_numeric_row_count, 0),
        'non_candidate_rows', coalesce(f.sellout_non_candidate_row_count, 0),
        'positive_quantity_sum', f.sellout_positive_quantity_sum,
        'positive_litres_sum', f.sellout_positive_litres_sum,
        'aggregate_lpu_candidate', f.sellout_lpu_candidate,
        'row_lpu_distinct_count', coalesce(f.sellout_row_lpu_distinct_count, 0),
        'row_lpu_min', f.sellout_row_lpu_min,
        'row_lpu_max', f.sellout_row_lpu_max,
        'row_lpu_spread', f.sellout_row_lpu_spread,
        'row_lpu_spread_ratio', f.sellout_row_lpu_spread_ratio,
        'name_candidate_count', coalesce(f.sellout_name_candidate_count, 0),
        'family_candidate_count', coalesce(f.sellout_family_candidate_count, 0)
      ),
      'ka', jsonb_build_object(
        'rows', coalesce(f.ka_row_count, 0),
        'positive_rows', coalesce(f.ka_positive_row_count, 0),
        'return_rows', coalesce(f.ka_return_row_count, 0),
        'invalid_numeric_rows', coalesce(f.ka_invalid_numeric_row_count, 0),
        'non_candidate_rows', coalesce(f.ka_non_candidate_row_count, 0),
        'positive_quantity_sum', f.ka_positive_quantity_sum,
        'positive_litres_sum', f.ka_positive_litres_sum,
        'aggregate_lpu_candidate', f.ka_lpu_candidate,
        'row_lpu_distinct_count', coalesce(f.ka_row_lpu_distinct_count, 0),
        'row_lpu_min', f.ka_row_lpu_min,
        'row_lpu_max', f.ka_row_lpu_max,
        'row_lpu_spread', f.ka_row_lpu_spread,
        'row_lpu_spread_ratio', f.ka_row_lpu_spread_ratio,
        'name_candidate_count', coalesce(f.ka_name_candidate_count, 0)
      ),
      'lpu_source_variance', jsonb_build_object(
        'absolute', f.lpu_source_variance,
        'ratio', f.lpu_source_variance_ratio
      ),
      'conversion_graph', jsonb_build_object(
        'component_key', f.component_key,
        'candidate', case when not coalesce(f.graph_has_conflict, false) and f.graph_lpu_num is not null and f.graph_lpu_den is not null then f.graph_lpu_num / f.graph_lpu_den end,
        'candidate_numerator', f.graph_lpu_num,
        'candidate_denominator', f.graph_lpu_den,
        'anchor_count', coalesce(f.graph_anchor_count, 0),
        'has_conflict', coalesce(f.graph_has_conflict, false),
        'anchor_candidates', coalesce(f.graph_candidates, '[]'::jsonb),
        'component_family_candidate_count', coalesce(f.component_family_candidate_count, 0),
        'direct_family_product_count', coalesce(f.direct_family_product_count, 0),
        'conversion_delta_lpu', f.conversion_delta_lpu
      ),
      'quantity_uom', jsonb_build_object(
        'candidate_count', coalesce(f.uom_candidate_count, 0),
        'value', f.final_quantity_uom,
        'state', f.quantity_uom_state
      ),
      'source_pending_attributes', jsonb_build_array('units_per_case','unit_volume_ml','canonical_stock_variant_code','replenishment_variant_code')
    ),
    v_effective_at
  from final f
  left join public.product_families pf
    on pf.scope_key = v_scope
   and pf.normalized_name = f.final_family_key;

  if exists (
    select 1
    from public.product_variant_resolutions r
    where r.run_id = v_run_id
      and r.conversion_component_key is not null
      and r.family_source = 'SELLOUT'
      and r.family_resolution_state = 'RESOLVED'
    group by r.conversion_component_key
    having count(distinct r.family_id) > 1
  ) then
    raise exception 'Conversion graph connects products with conflicting Sellout family evidence' using errcode = '23514';
  end if;

  if exists (
    select 1 from public.product_variant_resolutions
    where run_id = v_run_id
      and lpu_resolution_state = 'BLOCKED'
      and lpu_verification_state = 'unit_inconsistent'
  ) then
    raise exception 'Conversion graph produced conflicting LPU candidates' using errcode = '23514';
  end if;

  -- Exact litre conservation uses the stored rational LPU evidence and the
  -- representative source/target quantities. This avoids a hidden 9-decimal gate.
  if exists (
    select 1
    from public.product_conversion_edges e
    join public.product_variant_resolutions s
      on s.run_id = e.run_id and s.product_code = e.source_product_code
    join public.product_variant_resolutions t
      on t.run_id = e.run_id and t.product_code = e.target_product_code
    where e.run_id = v_run_id
      and s.lpu_resolution_state = 'RESOLVED'
      and t.lpu_resolution_state = 'RESOLVED'
      and s.lpu_numerator * e.source_quantity_basis * t.lpu_denominator
          <> t.lpu_numerator * e.target_quantity_basis * s.lpu_denominator
  ) then
    raise exception 'Resolved LPU evidence violates a PRODUCT_CONVERSION litre-conservation edge' using errcode = '23514';
  end if;

  select count(*) into v_variant_count from public.product_variant_resolutions where run_id = v_run_id;

  update public.product_variant_resolutions previous
  set valid_to = v_effective_at
  from public.product_domain_heads h
  where h.scope_key = v_scope
    and previous.run_id = h.active_run_id
    and h.active_run_id <> v_run_id
    and previous.valid_to is null;

  update public.product_variants
  set current_source_state = 'NOT_PRESENT', updated_at = now()
  where scope_key = v_scope;

  insert into public.product_variants(
    scope_key, product_code, product_name, product_name_resolution_state,
    family_id, family_resolution_state, family_source,
    quantity_uom, quantity_uom_resolution_state, quantity_uom_source,
    units_per_case, unit_volume_ml, canonical_stock_variant_code, replenishment_variant_code, volume_tracked,
    sellout_lpu_candidate, ka_lpu_candidate, package_lpu_candidate,
    lpu_numerator, lpu_denominator, lpu_resolution_state, lpu_source, lpu_verification_state,
    lpu_source_variance, lpu_source_variance_ratio, conversion_delta_lpu,
    conversion_component_key, has_conversion,
    current_source_state, active_run_id, current_resolution
  )
  select
    r.scope_key, r.product_code, r.product_name, r.product_name_resolution_state,
    r.family_id, r.family_resolution_state, r.family_source,
    r.quantity_uom, r.quantity_uom_resolution_state, r.quantity_uom_source,
    r.units_per_case, r.unit_volume_ml, r.canonical_stock_variant_code, r.replenishment_variant_code, r.volume_tracked,
    r.sellout_lpu_candidate, r.ka_lpu_candidate, r.package_lpu_candidate,
    r.lpu_numerator, r.lpu_denominator, r.lpu_resolution_state, r.lpu_source, r.lpu_verification_state,
    r.lpu_source_variance, r.lpu_source_variance_ratio, r.conversion_delta_lpu,
    r.conversion_component_key, r.has_conversion,
    'PRESENT', r.run_id, r.resolution_evidence
  from public.product_variant_resolutions r
  where r.run_id = v_run_id
  on conflict (scope_key, product_code) do update set
    product_name = excluded.product_name,
    product_name_resolution_state = excluded.product_name_resolution_state,
    family_id = excluded.family_id,
    family_resolution_state = excluded.family_resolution_state,
    family_source = excluded.family_source,
    quantity_uom = excluded.quantity_uom,
    quantity_uom_resolution_state = excluded.quantity_uom_resolution_state,
    quantity_uom_source = excluded.quantity_uom_source,
    units_per_case = excluded.units_per_case,
    unit_volume_ml = excluded.unit_volume_ml,
    canonical_stock_variant_code = excluded.canonical_stock_variant_code,
    replenishment_variant_code = excluded.replenishment_variant_code,
    volume_tracked = excluded.volume_tracked,
    sellout_lpu_candidate = excluded.sellout_lpu_candidate,
    ka_lpu_candidate = excluded.ka_lpu_candidate,
    package_lpu_candidate = excluded.package_lpu_candidate,
    lpu_numerator = excluded.lpu_numerator,
    lpu_denominator = excluded.lpu_denominator,
    lpu_resolution_state = excluded.lpu_resolution_state,
    lpu_source = excluded.lpu_source,
    lpu_verification_state = excluded.lpu_verification_state,
    lpu_source_variance = excluded.lpu_source_variance,
    lpu_source_variance_ratio = excluded.lpu_source_variance_ratio,
    conversion_delta_lpu = excluded.conversion_delta_lpu,
    conversion_component_key = excluded.conversion_component_key,
    has_conversion = excluded.has_conversion,
    current_source_state = 'PRESENT',
    active_run_id = excluded.active_run_id,
    current_resolution = excluded.current_resolution,
    updated_at = now();

  select jsonb_build_object(
    'variant_count', v_variant_count,
    'conversion_observation_count', v_conversion_observation_count,
    'conversion_product_count', v_conversion_product_count,
    'conversion_component_count', count(distinct conversion_component_key) filter (where has_conversion),
    'directed_edge_count', v_edge_count,
    'family_count', count(distinct family_id) filter (where family_resolution_state = 'RESOLVED'),
    'product_name_resolved', count(*) filter (where product_name_resolution_state = 'RESOLVED'),
    'product_name_partial', count(*) filter (where product_name_resolution_state = 'PARTIAL'),
    'product_name_blocked', count(*) filter (where product_name_resolution_state = 'BLOCKED'),
    'family_resolved', count(*) filter (where family_resolution_state = 'RESOLVED'),
    'family_partial', count(*) filter (where family_resolution_state = 'PARTIAL'),
    'family_blocked', count(*) filter (where family_resolution_state = 'BLOCKED'),
    'family_resolution_coverage', case when count(*) > 0 then count(*) filter (where family_resolution_state = 'RESOLVED')::numeric / count(*)::numeric end,
    'quantity_uom_resolved', count(*) filter (where quantity_uom_resolution_state = 'RESOLVED'),
    'quantity_uom_partial', count(*) filter (where quantity_uom_resolution_state = 'PARTIAL'),
    'quantity_uom_blocked', count(*) filter (where quantity_uom_resolution_state = 'BLOCKED'),
    'lpu_resolved', count(*) filter (where lpu_resolution_state = 'RESOLVED'),
    'lpu_partial', count(*) filter (where lpu_resolution_state = 'PARTIAL'),
    'lpu_blocked', count(*) filter (where lpu_resolution_state = 'BLOCKED'),
    'litre_resolution_coverage', case when count(*) > 0 then count(*) filter (where lpu_resolution_state = 'RESOLVED')::numeric / count(*)::numeric end,
    'lpu_sellout', count(*) filter (where lpu_resolution_state = 'RESOLVED' and lpu_source = 'SELLOUT'),
    'lpu_ka', count(*) filter (where lpu_resolution_state = 'RESOLVED' and lpu_source = 'KA_DELIVERY'),
    'lpu_graph', count(*) filter (where lpu_resolution_state = 'RESOLVED' and lpu_source = 'CONVERSION_GRAPH'),
    'lpu_cross_source_verified', count(*) filter (where lpu_verification_state = 'cross_source_verified'),
    'lpu_sellout_verified', count(*) filter (where lpu_verification_state = 'sellout_verified'),
    'lpu_ka_verified', count(*) filter (where lpu_verification_state = 'ka_verified'),
    'lpu_derived_pending', count(*) filter (where lpu_verification_state = 'derived_pending'),
    'lpu_missing', count(*) filter (where lpu_verification_state = 'missing'),
    'lpu_cross_source_compared', count(*) filter (where sellout_lpu_candidate is not null and ka_lpu_candidate is not null),
    'lpu_source_variance_nonzero', count(*) filter (where coalesce(lpu_source_variance, 0) > 0),
    'volume_tracked_true', count(*) filter (where volume_tracked is true),
    'volume_tracked_unknown', count(*) filter (where volume_tracked is null),
    'conversion_family_resolved', count(*) filter (where has_conversion and family_resolution_state = 'RESOLVED'),
    'conversion_family_partial', count(*) filter (where has_conversion and family_resolution_state = 'PARTIAL'),
    'conversion_family_blocked', count(*) filter (where has_conversion and family_resolution_state = 'BLOCKED'),
    'conversion_lpu_resolved', count(*) filter (where has_conversion and lpu_resolution_state = 'RESOLVED'),
    'conversion_lpu_partial', count(*) filter (where has_conversion and lpu_resolution_state = 'PARTIAL'),
    'conversion_lpu_blocked', count(*) filter (where has_conversion and lpu_resolution_state = 'BLOCKED')
  ) into v_summary
  from public.product_variant_resolutions
  where run_id = v_run_id;

  update public.product_domain_runs
  set status = 'RESOLVED', summary = v_summary, resolved_at = v_effective_at
  where id = v_run_id;

  insert into public.product_domain_heads(scope_key, active_run_id)
  values (v_scope, v_run_id)
  on conflict (scope_key) do update
    set active_run_id = excluded.active_run_id, updated_at = now();

  return jsonb_build_object('run_id', v_run_id, 'reused', false, 'summary', v_summary);
end;
$$;

-- Viewer-safe canonical product surface. Raw staging rows, source row ranges,
-- run/publication identifiers and row-level provenance remain admin-only; bounded
-- aggregate LPU candidates/variance are exposed because 03U must explain conversion evidence.
create or replace function public.read_current_product_business_surface()
returns table (
  scope_key text,
  product_code text,
  product_name text,
  product_name_resolution_state text,
  family text,
  family_resolution_state text,
  family_source text,
  quantity_uom text,
  quantity_uom_resolution_state text,
  quantity_uom_source text,
  units_per_case numeric,
  unit_volume_ml numeric,
  canonical_stock_variant_code text,
  replenishment_variant_code text,
  volume_tracked boolean,
  sellout_lpu_candidate numeric,
  ka_lpu_candidate numeric,
  package_lpu_candidate numeric,
  lpu numeric,
  lpu_resolution_state text,
  lpu_source text,
  lpu_verification_state text,
  lpu_source_variance numeric,
  lpu_source_variance_ratio numeric,
  conversion_delta_lpu numeric,
  conversion_component_key text,
  has_conversion boolean
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    v.scope_key,
    v.product_code,
    v.product_name,
    v.product_name_resolution_state,
    f.display_name as family,
    v.family_resolution_state,
    v.family_source,
    v.quantity_uom,
    v.quantity_uom_resolution_state,
    v.quantity_uom_source,
    v.units_per_case,
    v.unit_volume_ml,
    v.canonical_stock_variant_code,
    v.replenishment_variant_code,
    v.volume_tracked,
    v.sellout_lpu_candidate,
    v.ka_lpu_candidate,
    v.package_lpu_candidate,
    v.lpu,
    v.lpu_resolution_state,
    v.lpu_source,
    v.lpu_verification_state,
    v.lpu_source_variance,
    v.lpu_source_variance_ratio,
    v.conversion_delta_lpu,
    v.conversion_component_key,
    v.has_conversion
  from public.product_variants v
  left join public.product_families f on f.id = v.family_id
  join public.product_domain_heads h
    on h.scope_key = v.scope_key
   and h.active_run_id = v.active_run_id
  where v.current_source_state = 'PRESENT'
  order by v.scope_key collate "C", v.product_code collate "C";
$$;

create or replace function public.read_current_product_domain_summary()
returns table (
  scope_key text,
  variant_count bigint,
  conversion_observation_count bigint,
  conversion_product_count bigint,
  conversion_component_count bigint,
  directed_edge_count bigint,
  family_count bigint,
  product_name_resolved bigint,
  product_name_partial bigint,
  product_name_blocked bigint,
  family_resolved bigint,
  family_partial bigint,
  family_blocked bigint,
  family_resolution_coverage numeric,
  quantity_uom_resolved bigint,
  quantity_uom_partial bigint,
  quantity_uom_blocked bigint,
  lpu_resolved bigint,
  lpu_partial bigint,
  lpu_blocked bigint,
  litre_resolution_coverage numeric,
  lpu_sellout bigint,
  lpu_ka bigint,
  lpu_graph bigint,
  lpu_cross_source_verified bigint,
  lpu_sellout_verified bigint,
  lpu_ka_verified bigint,
  lpu_derived_pending bigint,
  lpu_missing bigint,
  lpu_cross_source_compared bigint,
  lpu_source_variance_nonzero bigint,
  volume_tracked_true bigint,
  volume_tracked_unknown bigint
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select
    r.scope_key,
    coalesce((r.summary ->> 'variant_count')::bigint, 0),
    coalesce((r.summary ->> 'conversion_observation_count')::bigint, 0),
    coalesce((r.summary ->> 'conversion_product_count')::bigint, 0),
    coalesce((r.summary ->> 'conversion_component_count')::bigint, 0),
    coalesce((r.summary ->> 'directed_edge_count')::bigint, 0),
    coalesce((r.summary ->> 'family_count')::bigint, 0),
    coalesce((r.summary ->> 'product_name_resolved')::bigint, 0),
    coalesce((r.summary ->> 'product_name_partial')::bigint, 0),
    coalesce((r.summary ->> 'product_name_blocked')::bigint, 0),
    coalesce((r.summary ->> 'family_resolved')::bigint, 0),
    coalesce((r.summary ->> 'family_partial')::bigint, 0),
    coalesce((r.summary ->> 'family_blocked')::bigint, 0),
    (r.summary ->> 'family_resolution_coverage')::numeric,
    coalesce((r.summary ->> 'quantity_uom_resolved')::bigint, 0),
    coalesce((r.summary ->> 'quantity_uom_partial')::bigint, 0),
    coalesce((r.summary ->> 'quantity_uom_blocked')::bigint, 0),
    coalesce((r.summary ->> 'lpu_resolved')::bigint, 0),
    coalesce((r.summary ->> 'lpu_partial')::bigint, 0),
    coalesce((r.summary ->> 'lpu_blocked')::bigint, 0),
    (r.summary ->> 'litre_resolution_coverage')::numeric,
    coalesce((r.summary ->> 'lpu_sellout')::bigint, 0),
    coalesce((r.summary ->> 'lpu_ka')::bigint, 0),
    coalesce((r.summary ->> 'lpu_graph')::bigint, 0),
    coalesce((r.summary ->> 'lpu_cross_source_verified')::bigint, 0),
    coalesce((r.summary ->> 'lpu_sellout_verified')::bigint, 0),
    coalesce((r.summary ->> 'lpu_ka_verified')::bigint, 0),
    coalesce((r.summary ->> 'lpu_derived_pending')::bigint, 0),
    coalesce((r.summary ->> 'lpu_missing')::bigint, 0),
    coalesce((r.summary ->> 'lpu_cross_source_compared')::bigint, 0),
    coalesce((r.summary ->> 'lpu_source_variance_nonzero')::bigint, 0),
    coalesce((r.summary ->> 'volume_tracked_true')::bigint, 0),
    coalesce((r.summary ->> 'volume_tracked_unknown')::bigint, 0)
  from public.product_domain_heads h
  join public.product_domain_runs r on r.id = h.active_run_id
  where r.status = 'RESOLVED'
  order by r.scope_key collate "C";
$$;

revoke all on function public.product_family_key(text) from public, anon, authenticated;
revoke all on function public.product_lpu_evidence_aggregate(uuid, text) from public, anon, authenticated;
revoke all on function public.assert_current_product_source_batch(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.materialize_current_product_domain(text) from public, anon, authenticated;
revoke all on function public.read_current_product_business_surface() from public;
revoke all on function public.read_current_product_domain_summary() from public;

grant execute on function public.materialize_current_product_domain(text) to authenticated;
grant execute on function public.read_current_product_business_surface() to authenticated;
grant execute on function public.read_current_product_domain_summary() to authenticated;
