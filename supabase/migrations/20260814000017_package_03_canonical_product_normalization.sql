-- Package 03 corrective migration: canonical product normalization.
--
-- Business correction:
-- * paket.xlsx is NOT a runtime/upload source. It is one-time development/reference evidence.
-- * Raw split/package codes are normalized to one business-facing canonical code before any
--   product-based calculation (Sellout, KA, FKNS, warehouse stock, stock days, target,
--   forecast, safety stock, order need, etc.).
-- * STANDARD (Bira) components normalize smaller split codes into the main/largest stock code.
-- * HIGH_ALCOHOL (Distile) components normalize the case/multipack code in the opposite
--   direction into the single/retail product code.
-- * Exact canonical quantity is rational/numeric and is NEVER rounded for calculations.
--   Rounding belongs to UX presentation only.
--
-- Evidence frozen from the user-supplied workbook:
-- paket.xlsx SHA-256 = 51fb373ca178b68a8ddd29a6ea8f65f54162137c78aaccfb9b7f93805ffffdf2
-- rows = 331, product codes = 84, stable directed relations = 59, components = 36
-- canonical reference payload SHA-256 = fe87542ecdd62d8ef0fb2875dc65cc0179f7d8b1e2a02855e119d5b8b8773814
--
-- This is a FORWARD correction. Historical migrations 00015/00016 remain immutable.

update public.source_contract_versions
set is_active = false,
    retired_at = coalesce(retired_at, now())
where source_kind = 'PRODUCT_CONVERSION'
  and is_active;

create table if not exists public.product_conversion_reference_versions (
  id uuid primary key default gen_random_uuid(),
  scope_key text not null check (length(btrim(scope_key)) > 0),
  version text not null check (length(btrim(version)) > 0),
  evidence_file_name text not null,
  evidence_sha256 text not null check (evidence_sha256 ~ '^[a-f0-9]{64}$'),
  canonical_payload_sha256 text not null check (canonical_payload_sha256 ~ '^[a-f0-9]{64}$'),
  evidence_row_count integer not null check (evidence_row_count >= 0),
  product_code_count integer not null check (product_code_count >= 0),
  directed_relation_count integer not null check (directed_relation_count >= 0),
  component_count integer not null check (component_count >= 0),
  policy_version text not null,
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  unique (scope_key, version)
);

create unique index if not exists product_conversion_reference_one_active_per_scope
  on public.product_conversion_reference_versions(scope_key)
  where is_active;

create table if not exists public.product_conversion_reference_edges (
  reference_version_id uuid not null references public.product_conversion_reference_versions(id) on delete cascade,
  source_product_code text not null check (source_product_code ~ '^[0-9]+$'),
  target_product_code text not null check (target_product_code ~ '^[0-9]+$'),
  source_quantity_basis bigint not null check (source_quantity_basis > 0),
  target_quantity_basis bigint not null check (target_quantity_basis > 0),
  source_quantity_uom text not null check (length(btrim(source_quantity_uom)) > 0),
  target_quantity_uom text not null check (length(btrim(target_quantity_uom)) > 0),
  observation_count integer not null check (observation_count > 0),
  primary key (reference_version_id, source_product_code, target_product_code),
  check (source_product_code <> target_product_code)
);

create table if not exists public.product_canonical_mappings (
  reference_version_id uuid not null references public.product_conversion_reference_versions(id) on delete cascade,
  component_key text not null check (component_key ~ '^[0-9]+$'),
  raw_product_code text not null check (raw_product_code ~ '^[0-9]+$'),
  canonical_product_code text not null check (canonical_product_code ~ '^[0-9]+$'),
  canonical_quantity_numerator bigint not null check (canonical_quantity_numerator > 0),
  canonical_quantity_denominator bigint not null check (canonical_quantity_denominator > 0),
  normalization_policy text not null check (normalization_policy in ('STANDARD','HIGH_ALCOHOL')),
  policy_basis text not null check (length(btrim(policy_basis)) > 0),
  primary key (reference_version_id, raw_product_code)
);

alter table public.product_conversion_reference_versions enable row level security;
alter table public.product_conversion_reference_edges enable row level security;
alter table public.product_canonical_mappings enable row level security;

drop policy if exists product_conversion_reference_versions_admin_read on public.product_conversion_reference_versions;
drop policy if exists product_conversion_reference_edges_admin_read on public.product_conversion_reference_edges;
drop policy if exists product_canonical_mappings_admin_read on public.product_canonical_mappings;

create policy product_conversion_reference_versions_admin_read
  on public.product_conversion_reference_versions for select to authenticated using (public.is_admin());
create policy product_conversion_reference_edges_admin_read
  on public.product_conversion_reference_edges for select to authenticated using (public.is_admin());
create policy product_canonical_mappings_admin_read
  on public.product_canonical_mappings for select to authenticated using (public.is_admin());

grant select on public.product_conversion_reference_versions,
  public.product_conversion_reference_edges,
  public.product_canonical_mappings to authenticated;

insert into public.product_conversion_reference_versions(
  scope_key, version, evidence_file_name, evidence_sha256, canonical_payload_sha256,
  evidence_row_count, product_code_count, directed_relation_count, component_count,
  policy_version, is_active
) values (
  '1237',
  'paket-51fb373c-v1',
  'paket.xlsx',
  '51fb373ca178b68a8ddd29a6ea8f65f54162137c78aaccfb9b7f93805ffffdf2',
  'fe87542ecdd62d8ef0fb2875dc65cc0179f7d8b1e2a02855e119d5b8b8773814',
  331, 84, 59, 36,
  'canonical-main-v2-high-alcohol-reverse-v1',
  true
)
on conflict (scope_key, version) do update set
  is_active = true,
  retired_at = null;

with ref as (
  select id from public.product_conversion_reference_versions
  where scope_key='1237' and version='paket-51fb373c-v1'
)
insert into public.product_conversion_reference_edges(
  reference_version_id, source_product_code, target_product_code,
  source_quantity_basis, target_quantity_basis, source_quantity_uom, target_quantity_uom, observation_count
)
select ref.id, v.source_product_code, v.target_product_code, v.source_quantity_basis,
       v.target_quantity_basis, v.source_quantity_uom, v.target_quantity_uom, v.observation_count
from ref
cross join (values
    ('150021', '154525', 1, 2, 'TVA', 'TVA', 14),
    ('150021', '154548', 1, 4, 'TVA', 'TVA', 8),
    ('150137', '151463', 1, 2, 'KL', 'KL', 3),
    ('150487', '151293', 1, 2, 'TVA', 'TVA', 12),
    ('150487', '154505', 1, 4, 'TVA', 'TVA', 15),
    ('150782', '151904', 1, 4, 'KL', 'KL', 3),
    ('150782', '151910', 1, 2, 'KL', 'KL', 4),
    ('150783', '151942', 1, 4, 'TVA', 'TVA', 1),
    ('150783', '151943', 1, 2, 'TVA', 'TVA', 1),
    ('150784', '152046', 1, 2, 'KL', 'KL', 28),
    ('151247', '151436', 1, 2, 'KL', 'KL', 5),
    ('151247', '154504', 1, 4, 'KL', 'KL', 6),
    ('151271', '151448', 1, 2, 'TVA', 'TVA', 9),
    ('151271', '154012', 1, 4, 'TVA', 'TVA', 4),
    ('151335', '154506', 1, 2, 'KAS', 'KAS', 2),
    ('151335', '154547', 1, 4, 'KAS', 'KAS', 2),
    ('151384', '152782', 1, 4, 'KL', 'KL', 2),
    ('151384', '154510', 1, 2, 'KL', 'KL', 5),
    ('151420', '154020', 1, 4, 'KL', 'KL', 10),
    ('151428', '154527', 1, 2, 'TVA', 'TVA', 4),
    ('151830', '154558', 1, 2, 'KL', 'KL', 1),
    ('151830', '154559', 1, 4, 'KL', 'KL', 5),
    ('151918', '154513', 1, 2, 'KL', 'KL', 2),
    ('151942', '150783', 4, 1, 'TVA', 'TVA', 1),
    ('151943', '150783', 2, 1, 'TVA', 'TVA', 1),
    ('151961', '152716', 1, 2, 'KL', 'KL', 2),
    ('152208', '152301', 1, 12, 'KL', 'ADT', 1),
    ('152221', '152312', 1, 6, 'KL', 'ADT', 1),
    ('152222', '152313', 1, 12, 'KL', 'ADT', 8),
    ('152223', '152314', 1, 12, 'KL', 'ADT', 11),
    ('152224', '152315', 1, 24, 'KL', 'ADT', 9),
    ('152225', '152316', 1, 24, 'KL', 'ADT', 7),
    ('152227', '152318', 1, 6, 'KL', 'ADT', 6),
    ('152236', '152327', 1, 6, 'KL', 'ADT', 11),
    ('152313', '152222', 12, 1, 'ADT', 'KL', 1),
    ('152327', '152236', 6, 1, 'ADT', 'KL', 1),
    ('152422', '152547', 1, 2, 'KL', 'KL', 4),
    ('152422', '152548', 1, 4, 'KL', 'KL', 12),
    ('152471', '152733', 1, 4, 'KL', 'KL', 14),
    ('152542', '152710', 1, 4, 'KL', 'KL', 1),
    ('152608', '154535', 1, 2, 'TVA', 'TVA', 22),
    ('152644', '154539', 1, 2, 'TVA', 'TVA', 8),
    ('152644', '154555', 1, 4, 'TVA', 'TVA', 8),
    ('152733', '152417', 4, 1, 'KL', 'KL', 1),
    ('152747', '152755', 1, 24, 'KL', 'ADT', 6),
    ('152748', '152756', 1, 12, 'KL', 'ADT', 8),
    ('152749', '152757', 1, 12, 'KL', 'ADT', 7),
    ('152751', '152758', 1, 6, 'KL', 'ADT', 7),
    ('152752', '152759', 1, 6, 'KL', 'ADT', 6),
    ('152753', '152763', 1, 12, 'KL', 'ADT', 4),
    ('152754', '152764', 1, 6, 'KL', 'ADT', 7),
    ('152763', '152753', 12, 1, 'ADT', 'KL', 1),
    ('152764', '152754', 6, 1, 'ADT', 'KL', 1),
    ('152782', '151384', 4, 1, 'KL', 'KL', 1),
    ('152949', '152950', 6, 1, 'ADT', 'KL', 1),
    ('152950', '152949', 1, 6, 'KL', 'ADT', 2),
    ('154525', '150021', 2, 1, 'TVA', 'TVA', 1),
    ('154548', '150021', 4, 1, 'TVA', 'TVA', 1),
    ('154555', '152644', 4, 1, 'TVA', 'TVA', 2)
) as v(source_product_code, target_product_code, source_quantity_basis, target_quantity_basis,
       source_quantity_uom, target_quantity_uom, observation_count)
on conflict (reference_version_id, source_product_code, target_product_code) do nothing;

with ref as (
  select id from public.product_conversion_reference_versions
  where scope_key='1237' and version='paket-51fb373c-v1'
)
insert into public.product_canonical_mappings(
  reference_version_id, component_key, raw_product_code, canonical_product_code,
  canonical_quantity_numerator, canonical_quantity_denominator, normalization_policy, policy_basis
)
select ref.id, v.component_key, v.raw_product_code, v.canonical_product_code,
       v.canonical_quantity_numerator, v.canonical_quantity_denominator,
       v.normalization_policy, v.policy_basis
from ref
cross join (values
    ('150021', '150021', '150021', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('150137', '150137', '150137', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('150487', '150487', '150487', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('150782', '150782', '150782', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('150783', '150783', '150783', 1, 1, 'STANDARD', 'REFERENCE_STANDARD_UOM'),
    ('150784', '150784', '150784', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('151247', '151247', '151247', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('151271', '151271', '151271', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('150487', '151293', '150487', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('151335', '151335', '151335', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('151384', '151384', '151384', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('151420', '151420', '151420', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('151428', '151428', '151428', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('151247', '151436', '151247', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('151271', '151448', '151271', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('150137', '151463', '150137', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('151830', '151830', '151830', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('150782', '151904', '150782', 1, 4, 'STANDARD', 'SELLOUT_BIRA'),
    ('150782', '151910', '150782', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('151918', '151918', '151918', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('150783', '151942', '150783', 1, 4, 'STANDARD', 'REFERENCE_STANDARD_UOM'),
    ('150783', '151943', '150783', 1, 2, 'STANDARD', 'REFERENCE_STANDARD_UOM'),
    ('151961', '151961', '151961', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('150784', '152046', '150784', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('152301', '152208', '152301', 12, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152312', '152221', '152312', 6, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152313', '152222', '152313', 12, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152314', '152223', '152314', 12, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152315', '152224', '152315', 24, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152316', '152225', '152316', 24, 1, 'HIGH_ALCOHOL', 'REFERENCE_KL_ADT'),
    ('152318', '152227', '152318', 6, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152327', '152236', '152327', 6, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152301', '152301', '152301', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152312', '152312', '152312', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152313', '152313', '152313', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152314', '152314', '152314', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152315', '152315', '152315', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152316', '152316', '152316', 1, 1, 'HIGH_ALCOHOL', 'REFERENCE_KL_ADT'),
    ('152318', '152318', '152318', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152327', '152327', '152327', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152471', '152417', '152471', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('152422', '152422', '152422', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('152471', '152471', '152471', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('152542', '152542', '152542', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('152422', '152547', '152422', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('152422', '152548', '152422', 1, 4, 'STANDARD', 'SELLOUT_BIRA'),
    ('152608', '152608', '152608', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('152644', '152644', '152644', 1, 1, 'STANDARD', 'SELLOUT_BIRA'),
    ('152542', '152710', '152542', 1, 4, 'STANDARD', 'SELLOUT_BIRA'),
    ('151961', '152716', '151961', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('152471', '152733', '152471', 1, 4, 'STANDARD', 'SELLOUT_BIRA'),
    ('152755', '152747', '152755', 24, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152756', '152748', '152756', 12, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152757', '152749', '152757', 12, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152758', '152751', '152758', 6, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152759', '152752', '152759', 6, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152763', '152753', '152763', 12, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152764', '152754', '152764', 6, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152755', '152755', '152755', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152756', '152756', '152756', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152757', '152757', '152757', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152758', '152758', '152758', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152759', '152759', '152759', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152763', '152763', '152763', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152764', '152764', '152764', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('151384', '152782', '151384', 1, 4, 'STANDARD', 'SELLOUT_BIRA'),
    ('152949', '152949', '152949', 1, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('152949', '152950', '152949', 6, 1, 'HIGH_ALCOHOL', 'SELLOUT_DISTILE'),
    ('151271', '154012', '151271', 1, 4, 'STANDARD', 'SELLOUT_BIRA'),
    ('151420', '154020', '151420', 1, 4, 'STANDARD', 'SELLOUT_BIRA'),
    ('151247', '154504', '151247', 1, 4, 'STANDARD', 'SELLOUT_BIRA'),
    ('150487', '154505', '150487', 1, 4, 'STANDARD', 'SELLOUT_BIRA'),
    ('151335', '154506', '151335', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('151384', '154510', '151384', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('151918', '154513', '151918', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('150021', '154525', '150021', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('151428', '154527', '151428', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('152608', '154535', '152608', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('152644', '154539', '152644', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('151335', '154547', '151335', 1, 4, 'STANDARD', 'SELLOUT_BIRA'),
    ('150021', '154548', '150021', 1, 4, 'STANDARD', 'SELLOUT_BIRA'),
    ('152644', '154555', '152644', 1, 4, 'STANDARD', 'SELLOUT_BIRA'),
    ('151830', '154558', '151830', 1, 2, 'STANDARD', 'SELLOUT_BIRA'),
    ('151830', '154559', '151830', 1, 4, 'STANDARD', 'SELLOUT_BIRA')
) as v(component_key, raw_product_code, canonical_product_code,
       canonical_quantity_numerator, canonical_quantity_denominator, normalization_policy, policy_basis)
on conflict (reference_version_id, raw_product_code) do nothing;

do $$
declare v_ref uuid;
begin
  select id into v_ref
  from public.product_conversion_reference_versions
  where scope_key='1237' and version='paket-51fb373c-v1' and is_active;

  if v_ref is null then
    raise exception 'Active canonical product reference is missing for scope 1237' using errcode='23514';
  end if;
  if (select count(*) from public.product_conversion_reference_edges where reference_version_id=v_ref) <> 59 then
    raise exception 'Canonical product reference must contain exactly 59 directed relations' using errcode='23514';
  end if;
  if (select coalesce(sum(observation_count),0) from public.product_conversion_reference_edges where reference_version_id=v_ref) <> 331 then
    raise exception 'Canonical product reference must conserve exactly 331 paket.xlsx observations' using errcode='23514';
  end if;
  if (select count(*) from public.product_canonical_mappings where reference_version_id=v_ref) <> 84 then
    raise exception 'Canonical product reference must contain exactly 84 mapped product codes' using errcode='23514';
  end if;
  if (select count(distinct canonical_product_code) from public.product_canonical_mappings where reference_version_id=v_ref) <> 36 then
    raise exception 'Canonical product reference must resolve exactly 36 canonical products/components' using errcode='23514';
  end if;

  if exists (
    select 1 from public.product_canonical_mappings m
    where m.reference_version_id=v_ref
      and not exists (
        select 1 from public.product_canonical_mappings c
        where c.reference_version_id=v_ref
          and c.raw_product_code=m.canonical_product_code
          and c.canonical_product_code=m.canonical_product_code
          and c.canonical_quantity_numerator=c.canonical_quantity_denominator
      )
  ) then
    raise exception 'Every canonical product must have an identity mapping' using errcode='23514';
  end if;

  if exists (
    select 1
    from public.product_conversion_reference_edges e
    join public.product_canonical_mappings s
      on s.reference_version_id=e.reference_version_id and s.raw_product_code=e.source_product_code
    join public.product_canonical_mappings t
      on t.reference_version_id=e.reference_version_id and t.raw_product_code=e.target_product_code
    where e.reference_version_id=v_ref
      and (
        e.source_quantity_basis::numeric * s.canonical_quantity_numerator::numeric * t.canonical_quantity_denominator::numeric
        <>
        e.target_quantity_basis::numeric * t.canonical_quantity_numerator::numeric * s.canonical_quantity_denominator::numeric
      )
  ) then
    raise exception 'Canonical product mapping violates an exact paket.xlsx conversion relation' using errcode='23514';
  end if;
end;
$$;

create or replace function public.resolve_canonical_product(p_scope_key text, p_product_code text)
returns table (
  reference_version text,
  raw_product_code text,
  canonical_product_code text,
  canonical_quantity_numerator bigint,
  canonical_quantity_denominator bigint,
  normalization_policy text
)
language plpgsql stable security definer set search_path = pg_catalog, public
as $$
declare
  v_scope text := btrim(p_scope_key);
  v_code text := btrim(p_product_code);
  v_ref public.product_conversion_reference_versions;
begin
  if v_scope is null or v_scope = '' then
    raise exception 'Product normalization scope is required' using errcode='22023';
  end if;
  if v_code is null or v_code !~ '^[0-9]+$' then
    raise exception 'Product code must be numeric text' using errcode='22023';
  end if;

  select * into v_ref
  from public.product_conversion_reference_versions
  where scope_key=v_scope and is_active;

  if v_ref.id is null then
    raise exception 'No active product normalization reference exists for scope %', v_scope using errcode='55000';
  end if;

  return query
  select v_ref.version, v_code,
         coalesce(m.canonical_product_code, v_code),
         coalesce(m.canonical_quantity_numerator,1::bigint),
         coalesce(m.canonical_quantity_denominator,1::bigint),
         coalesce(m.normalization_policy,'IDENTITY')
  from (select 1) x
  left join public.product_canonical_mappings m
    on m.reference_version_id=v_ref.id and m.raw_product_code=v_code;
end;
$$;

create or replace function public.canonical_product_code(p_scope_key text, p_product_code text)
returns text
language sql stable security definer set search_path = pg_catalog, public
as $$
  select r.canonical_product_code
  from public.resolve_canonical_product(p_scope_key,p_product_code) r;
$$;

create or replace function public.canonical_product_quantity(p_scope_key text, p_product_code text, p_raw_quantity numeric)
returns numeric
language sql stable security definer set search_path = pg_catalog, public
as $$
  select case when p_raw_quantity is null then null
    else p_raw_quantity * r.canonical_quantity_numerator::numeric / r.canonical_quantity_denominator::numeric
  end
  from public.resolve_canonical_product(p_scope_key,p_product_code) r;
$$;

comment on function public.canonical_product_quantity(text,text,numeric) is
'Exact backend quantity normalization only. Never round this value for FKNS, stock, stock-days, targets, forecast, safety stock or order calculations. UX may round a copy for display.';

-- Internal canonical litre-per-unit evidence. Sellout is Geleneksel, KA_DELIVERY is Modern/KA.
-- Each raw row is first converted to exact canonical quantity; litre evidence is then aggregated
-- against the canonical quantity. This means split-code sales contribute to the same product LPU
-- without exposing split codes as separate business products.
create or replace function public.current_canonical_product_lpu(p_scope_key text)
returns table (
  canonical_product_code text,
  sellout_lpu_candidate numeric,
  ka_lpu_candidate numeric,
  active_lpu numeric,
  active_source text,
  sellout_positive_row_count bigint,
  ka_positive_row_count bigint
)
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with ref as (
    select id
    from public.product_conversion_reference_versions
    where scope_key=btrim(p_scope_key) and is_active
  ), current_batches as (
    select h.source_kind, b.id as batch_id
    from public.publication_heads h
    join public.publications p on p.id=h.active_publication_id
    join public.candidate_publications cp on cp.id=p.candidate_id
    join public.import_batches b on b.id=cp.batch_id and b.published_publication_id=p.id
    where h.scope_key=btrim(p_scope_key)
      and h.source_kind in ('SELLOUT','KA_DELIVERY')
      and b.status='PUBLISHED'
  ), source_rows as (
    select
      cb.source_kind,
      case cb.source_kind
        when 'SELLOUT' then btrim(s.payload->>'Malzeme Kodu')
        when 'KA_DELIVERY' then btrim(s.payload->>'Ürün Kodu')
      end as raw_product_code,
      case when coalesce(s.payload->>'Miktar','') ~ '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$'
        then (s.payload->>'Miktar')::numeric end as raw_quantity,
      case when coalesce(s.payload->>'Litre','') ~ '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$'
        then (s.payload->>'Litre')::numeric end as litres
    from current_batches cb
    join public.staging_rows s on s.batch_id=cb.batch_id and s.row_status='VALID'
  ), normalized as (
    select
      sr.source_kind,
      coalesce(m.canonical_product_code,sr.raw_product_code) as canonical_product_code,
      sr.raw_quantity
        * coalesce(m.canonical_quantity_numerator,1::bigint)::numeric
        / coalesce(m.canonical_quantity_denominator,1::bigint)::numeric as canonical_quantity,
      sr.litres
    from source_rows sr
    cross join ref r
    left join public.product_canonical_mappings m
      on m.reference_version_id=r.id and m.raw_product_code=sr.raw_product_code
    where sr.raw_product_code ~ '^[0-9]+$'
      and sr.raw_quantity > 0
      and sr.litres > 0
  ), grouped as (
    select
      source_kind,
      canonical_product_code,
      count(*)::bigint as positive_row_count,
      sum(canonical_quantity) as canonical_quantity_sum,
      sum(litres) as litres_sum,
      sum(litres)/nullif(sum(canonical_quantity),0) as lpu_candidate
    from normalized
    group by source_kind, canonical_product_code
  ), pivoted as (
    select
      canonical_product_code,
      max(lpu_candidate) filter (where source_kind='SELLOUT') as sellout_lpu_candidate,
      max(lpu_candidate) filter (where source_kind='KA_DELIVERY') as ka_lpu_candidate,
      max(positive_row_count) filter (where source_kind='SELLOUT') as sellout_positive_row_count,
      max(positive_row_count) filter (where source_kind='KA_DELIVERY') as ka_positive_row_count
    from grouped
    group by canonical_product_code
  )
  select
    p.canonical_product_code,
    p.sellout_lpu_candidate,
    p.ka_lpu_candidate,
    coalesce(p.sellout_lpu_candidate,p.ka_lpu_candidate) as active_lpu,
    case when p.sellout_lpu_candidate is not null then 'SELLOUT'
         when p.ka_lpu_candidate is not null then 'KA_DELIVERY' end as active_source,
    coalesce(p.sellout_positive_row_count,0),
    coalesce(p.ka_positive_row_count,0)
  from pivoted p;
$$;

create or replace function public.canonical_product_lpu(p_scope_key text, p_product_code text)
returns numeric
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  select l.active_lpu
  from public.current_canonical_product_lpu(p_scope_key) l
  where l.canonical_product_code=public.canonical_product_code(p_scope_key,p_product_code);
$$;

comment on function public.current_canonical_product_lpu(text) is
'Internal litre-per-canonical-unit evidence. Positive Sellout (Geleneksel) has priority over positive KA (Modern); split codes are normalized before aggregation.';
comment on function public.canonical_product_lpu(text,text) is
'Internal exact litre-per-canonical-unit resolver. Missing positive evidence returns NULL, never zero.';

revoke all on function public.resolve_canonical_product(text,text) from public, anon, authenticated;
revoke all on function public.canonical_product_code(text,text) from public, anon, authenticated;
revoke all on function public.canonical_product_quantity(text,text,numeric) from public, anon, authenticated;
revoke all on function public.current_canonical_product_lpu(text) from public, anon, authenticated;
revoke all on function public.canonical_product_lpu(text,text) from public, anon, authenticated;
revoke all on function public.materialize_current_product_domain(text) from authenticated;

revoke all on function public.read_current_product_business_surface() from authenticated;
revoke all on function public.read_current_product_domain_summary() from authenticated;

comment on function public.read_current_product_business_surface() is
'Deprecated viewer surface. Package 03 is internal canonicalization infrastructure; no standalone Product Master UX is approved.';
comment on function public.read_current_product_domain_summary() is
'Deprecated viewer summary. Package 03 is internal canonicalization infrastructure; technical reference evidence is admin/audit only.';

create or replace function public.reconcile_product_domain_freshness(p_scope_key text)
returns jsonb
language plpgsql security definer set search_path = pg_catalog, public
as $$
declare
  v_scope text := btrim(p_scope_key);
  v_sellout_publication uuid;
  v_ka_publication uuid;
  v_reference_version text;
  v_attempted_at timestamptz := clock_timestamp();
begin
  perform public.assert_import_admin();
  if v_scope is null or v_scope = '' then
    raise exception 'Product domain scope is required' using errcode='22023';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('product-domain:' || v_scope,0));

  select active_publication_id into v_sellout_publication
  from public.publication_heads where source_kind='SELLOUT' and scope_key=v_scope;
  select active_publication_id into v_ka_publication
  from public.publication_heads where source_kind='KA_DELIVERY' and scope_key=v_scope;
  select version into v_reference_version
  from public.product_conversion_reference_versions where scope_key=v_scope and is_active;

  insert into public.product_domain_heads(
    scope_key, active_run_id, freshness_state, freshness_error, stale_since, last_attempted_at,
    expected_conversion_publication_id, expected_sellout_publication_id, expected_ka_publication_id, updated_at
  ) values (
    v_scope, null, 'PENDING_SOURCES', null, null, v_attempted_at,
    null, v_sellout_publication, v_ka_publication, v_attempted_at
  )
  on conflict (scope_key) do update set
    active_run_id=null,
    expected_conversion_publication_id=null,
    expected_sellout_publication_id=excluded.expected_sellout_publication_id,
    expected_ka_publication_id=excluded.expected_ka_publication_id,
    last_attempted_at=excluded.last_attempted_at,
    updated_at=excluded.updated_at;

  if v_reference_version is null or v_sellout_publication is null or v_ka_publication is null then
    update public.product_domain_heads
    set freshness_state='PENDING_SOURCES', freshness_error=null, stale_since=null, updated_at=v_attempted_at
    where scope_key=v_scope;
    return jsonb_build_object('scope_key',v_scope,'reference_version',v_reference_version,
      'freshness_state','PENDING_SOURCES','is_fresh',false);
  end if;

  update public.product_domain_heads
  set freshness_state='FRESH', freshness_error=null, stale_since=null, updated_at=v_attempted_at
  where scope_key=v_scope;

  return jsonb_build_object('scope_key',v_scope,'reference_version',v_reference_version,
    'freshness_state','FRESH','is_fresh',true);
end;
$$;

create or replace function public.read_current_product_domain_freshness()
returns table (
  scope_key text,
  freshness_state text,
  freshness_error text,
  is_fresh boolean,
  stale_since timestamptz,
  last_attempted_at timestamptz
)
language sql stable security definer set search_path = pg_catalog, public
as $$
  with scopes as (
    select scope_key from public.product_domain_heads
    union select scope_key from public.product_conversion_reference_versions where is_active
    union select scope_key from public.publication_heads where source_kind in ('SELLOUT','KA_DELIVERY')
  ), current_state as (
    select s.scope_key, h.freshness_state as stored_state, h.freshness_error, h.stale_since, h.last_attempted_at,
      exists(select 1 from public.product_conversion_reference_versions r where r.scope_key=s.scope_key and r.is_active) as has_reference,
      (select active_publication_id from public.publication_heads p where p.source_kind='SELLOUT' and p.scope_key=s.scope_key) as sellout_publication_id,
      (select active_publication_id from public.publication_heads p where p.source_kind='KA_DELIVERY' and p.scope_key=s.scope_key) as ka_publication_id
    from scopes s left join public.product_domain_heads h on h.scope_key=s.scope_key
  )
  select c.scope_key,
    case when c.stored_state='BLOCKED' then 'BLOCKED'
      when not c.has_reference or c.sellout_publication_id is null or c.ka_publication_id is null then 'PENDING_SOURCES'
      else 'FRESH' end,
    case when c.stored_state='BLOCKED' and public.is_admin() then c.freshness_error
      when c.stored_state='BLOCKED' then 'Ürün normalizasyonu doğrulaması engellendi.'
      else null end,
    (c.stored_state is distinct from 'BLOCKED' and c.has_reference
      and c.sellout_publication_id is not null and c.ka_publication_id is not null),
    case when c.stored_state='BLOCKED' then c.stale_since else null end,
    c.last_attempted_at
  from current_state c;
$$;

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

  return v_publication_id;
end;
$$;

revoke all on function public.reconcile_product_domain_freshness(text) from public, anon, authenticated;
revoke all on function public.read_current_product_domain_freshness() from public;
grant execute on function public.reconcile_product_domain_freshness(text) to authenticated;
grant execute on function public.read_current_product_domain_freshness() to authenticated;

comment on table public.product_canonical_mappings is
'Internal canonical product reference. Split/package codes do not create separate business rows; all downstream product calculations normalize through this mapping first.';
comment on function public.read_current_product_domain_freshness() is
'Viewer-safe readiness only. paket.xlsx is a frozen internal reference, not a runtime upload/publication dependency.';
