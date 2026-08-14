-- Package 03: product-domain freshness invariance.
--
-- ORCHESTRATION ONLY. The accepted 20260813000015 materializer remains the sole owner of
-- product family, conversion graph, LPU, validity history and current-projection semantics.
-- This migration must not reimplement or relax those rules.

alter table public.product_domain_heads
  alter column active_run_id drop not null;

alter table public.product_domain_heads
  add column if not exists freshness_state text not null default 'PENDING_SOURCES'
    check (freshness_state in ('FRESH', 'STALE', 'BLOCKED', 'PENDING_SOURCES')),
  add column if not exists freshness_error text,
  add column if not exists stale_since timestamptz,
  add column if not exists last_attempted_at timestamptz,
  add column if not exists expected_conversion_publication_id uuid references public.publications(id),
  add column if not exists expected_sellout_publication_id uuid references public.publications(id),
  add column if not exists expected_ka_publication_id uuid references public.publications(id);

insert into public.product_domain_heads(scope_key, active_run_id, freshness_state, updated_at)
select distinct h.scope_key, null::uuid, 'PENDING_SOURCES', now()
from public.publication_heads h
where h.source_kind in ('PRODUCT_CONVERSION', 'SELLOUT', 'KA_DELIVERY')
on conflict (scope_key) do nothing;

with product_scopes as (
  select distinct h.scope_key
  from public.publication_heads h
  where h.source_kind in ('PRODUCT_CONVERSION', 'SELLOUT', 'KA_DELIVERY')
), current_heads as (
  select
    s.scope_key,
    (select h.active_publication_id from public.publication_heads h where h.source_kind='PRODUCT_CONVERSION' and h.scope_key=s.scope_key) as conversion_publication_id,
    (select h.active_publication_id from public.publication_heads h where h.source_kind='SELLOUT' and h.scope_key=s.scope_key) as sellout_publication_id,
    (select h.active_publication_id from public.publication_heads h where h.source_kind='KA_DELIVERY' and h.scope_key=s.scope_key) as ka_publication_id
  from product_scopes s
), classified as (
  select
    pdh.scope_key,
    ch.conversion_publication_id,
    ch.sellout_publication_id,
    ch.ka_publication_id,
    case
      when ch.conversion_publication_id is null
        or ch.sellout_publication_id is null
        or ch.ka_publication_id is null
      then 'PENDING_SOURCES'
      when r.id is not null
        and r.status = 'RESOLVED'
        and r.conversion_publication_id = ch.conversion_publication_id
        and r.sellout_publication_id = ch.sellout_publication_id
        and r.ka_publication_id = ch.ka_publication_id
      then 'FRESH'
      else 'STALE'
    end as calculated_state
  from public.product_domain_heads pdh
  left join current_heads ch on ch.scope_key = pdh.scope_key
  left join public.product_domain_runs r on r.id = pdh.active_run_id
)
update public.product_domain_heads pdh
set
  expected_conversion_publication_id = c.conversion_publication_id,
  expected_sellout_publication_id = c.sellout_publication_id,
  expected_ka_publication_id = c.ka_publication_id,
  freshness_state = c.calculated_state,
  freshness_error = null,
  stale_since = case when c.calculated_state='STALE' then coalesce(pdh.stale_since, now()) else null end,
  updated_at = now()
from classified c
where c.scope_key = pdh.scope_key;

create or replace function public.reconcile_product_domain_freshness(p_scope_key text)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
set statement_timeout = '75s'
as $$
declare
  v_scope text := btrim(p_scope_key);
  v_conversion_publication uuid;
  v_sellout_publication uuid;
  v_ka_publication uuid;
  v_active_run uuid;
  v_run public.product_domain_runs;
  v_result jsonb;
  v_result_run uuid;
  v_attempted_at timestamptz := clock_timestamp();
  v_error text;
begin
  perform public.assert_import_admin();

  if v_scope is null or v_scope = '' then
    raise exception 'Product domain scope is required' using errcode = '22023';
  end if;

  -- Same scope lock as accepted 00015. Direct materialization and freshness reconciliation
  -- therefore serialize without a second lock hierarchy.
  perform pg_advisory_xact_lock(hashtextextended('product-domain:' || v_scope, 0));

  select h.active_publication_id into v_conversion_publication
  from public.publication_heads h
  where h.source_kind='PRODUCT_CONVERSION' and h.scope_key=v_scope;

  select h.active_publication_id into v_sellout_publication
  from public.publication_heads h
  where h.source_kind='SELLOUT' and h.scope_key=v_scope;

  select h.active_publication_id into v_ka_publication
  from public.publication_heads h
  where h.source_kind='KA_DELIVERY' and h.scope_key=v_scope;

  insert into public.product_domain_heads(scope_key, active_run_id, freshness_state, updated_at)
  values (v_scope, null, 'PENDING_SOURCES', v_attempted_at)
  on conflict (scope_key) do nothing;

  select active_run_id into v_active_run
  from public.product_domain_heads
  where scope_key=v_scope
  for update;

  update public.product_domain_heads
  set
    expected_conversion_publication_id=v_conversion_publication,
    expected_sellout_publication_id=v_sellout_publication,
    expected_ka_publication_id=v_ka_publication,
    last_attempted_at=v_attempted_at,
    updated_at=v_attempted_at
  where scope_key=v_scope;

  if v_conversion_publication is null or v_sellout_publication is null or v_ka_publication is null then
    update public.product_domain_heads
    set freshness_state='PENDING_SOURCES', freshness_error=null, stale_since=null, updated_at=v_attempted_at
    where scope_key=v_scope;

    return jsonb_build_object('scope_key',v_scope,'freshness_state','PENDING_SOURCES','is_fresh',false);
  end if;

  if v_active_run is not null then
    select * into v_run from public.product_domain_runs where id=v_active_run;
  end if;

  if v_run.id is not null
    and v_run.status='RESOLVED'
    and v_run.conversion_publication_id=v_conversion_publication
    and v_run.sellout_publication_id=v_sellout_publication
    and v_run.ka_publication_id=v_ka_publication
  then
    update public.product_domain_heads
    set freshness_state='FRESH', freshness_error=null, stale_since=null, updated_at=v_attempted_at
    where scope_key=v_scope;

    return jsonb_build_object(
      'scope_key',v_scope,'run_id',v_active_run,'reused',true,'freshness_state','FRESH','is_fresh',true
    );
  end if;

  update public.product_domain_heads
  set freshness_state='STALE', freshness_error=null, stale_since=coalesce(stale_since,v_attempted_at), updated_at=v_attempted_at
  where scope_key=v_scope;

  begin
    -- Canonical accepted business semantics: call 00015; do not copy its logic here.
    v_result := public.materialize_current_product_domain(v_scope);
    v_result_run := nullif(v_result->>'run_id','')::uuid;

    if v_result_run is null then
      raise exception 'Product materialization returned no run id' using errcode='55000';
    end if;

    select * into v_run from public.product_domain_runs where id=v_result_run;

    if v_run.id is null
      or v_run.status <> 'RESOLVED'
      or v_run.conversion_publication_id <> v_conversion_publication
      or v_run.sellout_publication_id <> v_sellout_publication
      or v_run.ka_publication_id <> v_ka_publication
    then
      raise exception 'Resolved product run does not match the expected current publication triple' using errcode='55000';
    end if;

    if not exists (
      select 1 from public.product_domain_heads h
      where h.scope_key=v_scope and h.active_run_id=v_result_run
    ) then
      raise exception 'Resolved product run was not activated by the canonical materializer' using errcode='55000';
    end if;

    update public.product_domain_heads
    set
      freshness_state='FRESH',
      freshness_error=null,
      stale_since=null,
      expected_conversion_publication_id=v_conversion_publication,
      expected_sellout_publication_id=v_sellout_publication,
      expected_ka_publication_id=v_ka_publication,
      last_attempted_at=v_attempted_at,
      updated_at=clock_timestamp()
    where scope_key=v_scope;

    return v_result || jsonb_build_object('scope_key',v_scope,'freshness_state','FRESH','is_fresh',true);
  exception when others then
    -- The failed canonical materializer subtransaction rolls back before BLOCKED is written.
    v_error := sqlerrm;
    update public.product_domain_heads
    set
      freshness_state='BLOCKED',
      freshness_error=v_error,
      stale_since=coalesce(stale_since,v_attempted_at),
      expected_conversion_publication_id=v_conversion_publication,
      expected_sellout_publication_id=v_sellout_publication,
      expected_ka_publication_id=v_ka_publication,
      last_attempted_at=v_attempted_at,
      updated_at=clock_timestamp()
    where scope_key=v_scope;

    return jsonb_build_object('scope_key',v_scope,'freshness_state','BLOCKED','is_fresh',false,'error',v_error);
  end;
end;
$$;


create or replace function public.publish_candidate(p_candidate_id uuid, p_expected_active_publication_id uuid default null)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_candidate public.candidate_publications; v_batch public.import_batches; v_reconciliation public.import_reconciliations;
declare v_head public.publication_heads; v_publication_id uuid; v_next_version integer; v_has_head boolean;
begin
  perform public.assert_import_admin();
  select * into v_candidate from public.candidate_publications where id = p_candidate_id for update;
  if not found then raise exception 'Candidate publication was not found' using errcode = 'P0002'; end if;
  if v_candidate.status = 'PUBLISHED' then select id into v_publication_id from public.publications where candidate_id = p_candidate_id; return v_publication_id; end if;
  select * into v_batch from public.import_batches where id = v_candidate.batch_id for update;
  select * into v_reconciliation from public.import_reconciliations where id = v_candidate.reconciliation_id;
  if v_candidate.status <> 'READY' or v_batch.status <> 'CANDIDATE_READY' or v_reconciliation.status <> 'MATCHED' then
    raise exception 'Candidate is stale, blocked, or not reconciled' using errcode = '55000';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('package01:' || v_batch.source_kind || ':' || v_batch.scope_key, 0));
  select * into v_head from public.publication_heads where source_kind = v_batch.source_kind and scope_key = v_batch.scope_key for update;
  v_has_head := found;
  if v_has_head and v_head.active_publication_id is distinct from p_expected_active_publication_id then
    raise exception 'Active publication changed; refresh and retry with its current id' using errcode = '40001';
  end if;
  if not v_has_head and p_expected_active_publication_id is not null then raise exception 'No active publication exists for the expected id' using errcode = '40001'; end if;
  v_next_version := coalesce(v_head.version, 0) + 1;
  insert into public.publications (candidate_id, source_kind, scope_key, version, manifest, published_by)
  values (v_candidate.id, v_batch.source_kind, v_batch.scope_key, v_next_version, v_candidate.manifest, auth.uid()) returning id into v_publication_id;
  if v_has_head then update public.publications set superseded_at = now() where id = v_head.active_publication_id; end if;
  insert into public.publication_heads (source_kind, scope_key, active_publication_id, version)
  values (v_batch.source_kind, v_batch.scope_key, v_publication_id, v_next_version)
  on conflict (source_kind, scope_key) do update set active_publication_id = excluded.active_publication_id, version = excluded.version, updated_at = now();
  update public.candidate_publications set status = 'PUBLISHED', published_at = now() where id = v_candidate.id;
  update public.import_batches set status = 'PUBLISHED', published_publication_id = v_publication_id, completed_at = now() where id = v_batch.id;
  perform pg_notify('publication_changed', json_build_object('source_kind', v_batch.source_kind, 'scope_key', v_batch.scope_key, 'publication_id', v_publication_id, 'version', v_next_version)::text);
  if v_batch.source_kind in ('PRODUCT_CONVERSION', 'SELLOUT', 'KA_DELIVERY') then
    begin
      perform public.reconcile_product_domain_freshness(v_batch.scope_key);
    exception when others then
      -- Keep the valid Package 01 publication, but fail the dependent product read model closed.
      insert into public.product_domain_heads(
        scope_key, active_run_id, freshness_state, freshness_error, stale_since, last_attempted_at,
        expected_conversion_publication_id, expected_sellout_publication_id, expected_ka_publication_id, updated_at
      ) values (
        v_batch.scope_key, null, 'BLOCKED', sqlerrm, clock_timestamp(), clock_timestamp(),
        (select active_publication_id from public.publication_heads where source_kind='PRODUCT_CONVERSION' and scope_key=v_batch.scope_key),
        (select active_publication_id from public.publication_heads where source_kind='SELLOUT' and scope_key=v_batch.scope_key),
        (select active_publication_id from public.publication_heads where source_kind='KA_DELIVERY' and scope_key=v_batch.scope_key),
        clock_timestamp()
      )
      on conflict (scope_key) do update set
        freshness_state = 'BLOCKED',
        freshness_error = excluded.freshness_error,
        stale_since = coalesce(public.product_domain_heads.stale_since, excluded.stale_since),
        last_attempted_at = excluded.last_attempted_at,
        expected_conversion_publication_id = excluded.expected_conversion_publication_id,
        expected_sellout_publication_id = excluded.expected_sellout_publication_id,
        expected_ka_publication_id = excluded.expected_ka_publication_id,
        updated_at = excluded.updated_at;
    end;
  end if;

  return v_publication_id;
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
language sql
stable
security definer
set search_path = pg_catalog, public
as $$
  with live as (
    select
      h.scope_key,
      h.active_run_id,
      h.freshness_state as stored_state,
      h.freshness_error as raw_error,
      h.stale_since,
      h.last_attempted_at,
      h.expected_conversion_publication_id,
      h.expected_sellout_publication_id,
      h.expected_ka_publication_id,
      (select active_publication_id from public.publication_heads where source_kind='PRODUCT_CONVERSION' and scope_key=h.scope_key) as live_conversion_publication_id,
      (select active_publication_id from public.publication_heads where source_kind='SELLOUT' and scope_key=h.scope_key) as live_sellout_publication_id,
      (select active_publication_id from public.publication_heads where source_kind='KA_DELIVERY' and scope_key=h.scope_key) as live_ka_publication_id
    from public.product_domain_heads h
  ), classified as (
    select
      l.*,
      case
        when l.live_conversion_publication_id is null
          or l.live_sellout_publication_id is null
          or l.live_ka_publication_id is null
        then 'PENDING_SOURCES'
        when l.stored_state='BLOCKED'
          and l.expected_conversion_publication_id is not distinct from l.live_conversion_publication_id
          and l.expected_sellout_publication_id is not distinct from l.live_sellout_publication_id
          and l.expected_ka_publication_id is not distinct from l.live_ka_publication_id
        then 'BLOCKED'
        when r.status='RESOLVED'
          and r.conversion_publication_id=l.live_conversion_publication_id
          and r.sellout_publication_id=l.live_sellout_publication_id
          and r.ka_publication_id=l.live_ka_publication_id
        then 'FRESH'
        when l.expected_conversion_publication_id is distinct from l.live_conversion_publication_id
          or l.expected_sellout_publication_id is distinct from l.live_sellout_publication_id
          or l.expected_ka_publication_id is distinct from l.live_ka_publication_id
        then 'STALE'
        else 'STALE'
      end as calculated_state
    from live l
    left join public.product_domain_runs r on r.id=l.active_run_id
  )
  select
    c.scope_key,
    c.calculated_state,
    case
      when c.calculated_state='FRESH' then null
      when c.calculated_state='BLOCKED' and public.is_admin() then c.raw_error
      when c.calculated_state='BLOCKED' and c.raw_error like '%embedded scope does not match%' then 'Veri seti bayi/üretim yeri uyumsuzluğu tespit edildi.'
      when c.calculated_state='BLOCKED' and (c.raw_error like '%conflicting factors%' or c.raw_error like '%inconsistent factor paths%') then 'Dönüşüm katsayıları tutarsızlığı tespit edildi.'
      when c.calculated_state='BLOCKED' and c.raw_error like '%conflicting quantity UOM%' then 'Ölçü birimi uyumsuzluğu tespit edildi.'
      when c.calculated_state='BLOCKED' and (c.raw_error like '%non-canonical product code%' or c.raw_error like '%invalid product code%') then 'Geçersiz ürün kodu formatı tespit edildi.'
      when c.calculated_state='BLOCKED' and (c.raw_error like '%malformed numeric%' or c.raw_error like '%non-positive conversion quantity%') then 'Sayısal veri format hatası tespit edildi.'
      when c.calculated_state='BLOCKED' then 'Ürün etki alanı doğrulaması engellendi.'
      when c.calculated_state='STALE' then 'Ürün kaynak yayını değişti; güncel ürün çözümlemesi henüz doğrulanmadı.'
      else null
    end,
    (c.calculated_state='FRESH'),
    case when c.calculated_state in ('STALE','BLOCKED') then c.stale_since else null end,
    c.last_attempted_at
  from classified c
  order by c.scope_key collate "C";
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
    and h.freshness_state <> 'BLOCKED'
    and r.conversion_publication_id = (select active_publication_id from public.publication_heads where source_kind='PRODUCT_CONVERSION' and scope_key=h.scope_key)
    and r.sellout_publication_id = (select active_publication_id from public.publication_heads where source_kind='SELLOUT' and scope_key=h.scope_key)
    and r.ka_publication_id = (select active_publication_id from public.publication_heads where source_kind='KA_DELIVERY' and scope_key=h.scope_key)
  order by r.scope_key collate "C";
$$;


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
  join public.product_domain_runs r
    on r.id = h.active_run_id
   and r.status = 'RESOLVED'
  where v.current_source_state = 'PRESENT'
    and h.freshness_state <> 'BLOCKED'
    and r.conversion_publication_id = (select active_publication_id from public.publication_heads where source_kind='PRODUCT_CONVERSION' and scope_key=h.scope_key)
    and r.sellout_publication_id = (select active_publication_id from public.publication_heads where source_kind='SELLOUT' and scope_key=h.scope_key)
    and r.ka_publication_id = (select active_publication_id from public.publication_heads where source_kind='KA_DELIVERY' and scope_key=h.scope_key)
  order by v.scope_key collate "C", v.product_code collate "C";
$$;



revoke all on function public.reconcile_product_domain_freshness(text) from public, anon, authenticated;
revoke all on function public.read_current_product_domain_freshness() from public;
revoke all on function public.read_current_product_domain_summary() from public;
revoke all on function public.read_current_product_business_surface() from public;

grant execute on function public.reconcile_product_domain_freshness(text) to authenticated;
grant execute on function public.read_current_product_domain_freshness() to authenticated;
grant execute on function public.read_current_product_domain_summary() to authenticated;
grant execute on function public.read_current_product_business_surface() to authenticated;
grant execute on function public.publish_candidate(uuid, uuid) to authenticated;

comment on function public.reconcile_product_domain_freshness(text) is
  'Admin-only freshness orchestrator. Uses the accepted Package 03 materializer and never reimplements product/LPU business semantics.';
comment on function public.read_current_product_domain_freshness() is
  'Viewer-safe freshness status without run/publication/batch identifiers. Raw blocker details are visible only to admins.';
