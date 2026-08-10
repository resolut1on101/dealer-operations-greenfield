-- Package 02: canonical customer, Master snapshot, channel, status and organization resolution.
-- The generic Package 01 transport remains the import/publication boundary.

create type public.customer_status as enum ('ACTIVE', 'PASSIVE', 'CANCELLED', 'UNKNOWN');
create type public.customer_channel as enum ('OPEN', 'CLOSED', 'UNCLASSIFIED');

create table public.customer_master_snapshots (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.import_batches(id),
  publication_id uuid unique references public.publications(id),
  snapshot_key text not null,
  is_complete boolean not null default true,
  as_of_at timestamptz not null default now(),
  as_of_source text not null check (as_of_source in ('BUSINESS_CUTOFF', 'UPLOAD_TIME_FALLBACK')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique (snapshot_key, as_of_at)
);

create table public.customer_master_observations (
  id bigint generated always as identity primary key,
  snapshot_id uuid not null references public.customer_master_snapshots(id) on delete cascade,
  source_row_no bigint not null check (source_row_no > 0),
  customer_id text not null check (customer_id ~ '^500[0-9]+$'),
  customer_name text,
  trade_name text,
  raw_status text,
  raw_channel text,
  segment text,
  raw_representative text,
  raw_ssm text,
  raw_payload jsonb not null check (jsonb_typeof(raw_payload) = 'object'),
  source_staging_row_id bigint not null,
  source_payload_hash text not null check (source_payload_hash ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  unique (snapshot_id, source_row_no)
);

create table public.customer_representatives (
  id uuid primary key default gen_random_uuid(),
  normalized_name text not null unique,
  raw_names jsonb not null default '[]'::jsonb check (jsonb_typeof(raw_names) = 'array'),
  raw_ssm_names jsonb not null default '[]'::jsonb check (jsonb_typeof(raw_ssm_names) = 'array'),
  ssm_resolution_state text not null default 'UNRESOLVED' check (ssm_resolution_state in ('RESOLVED', 'MANUAL_REVIEW', 'UNRESOLVED')),
  canonical_ssm text,
  dominant_ratio numeric(8, 6),
  updated_at timestamptz not null default now()
);

create table public.customer_representative_ssm_resolutions (
  representative_id uuid not null references public.customer_representatives(id) on delete cascade,
  snapshot_id uuid not null references public.customer_master_snapshots(id) on delete cascade,
  canonical_ssm text,
  resolution_state text not null check (resolution_state in ('RESOLVED', 'MANUAL_REVIEW', 'UNRESOLVED')),
  dominant_ratio numeric(8, 6),
  known_active_count bigint not null check (known_active_count >= 0),
  raw_ssm_names jsonb not null default '[]'::jsonb check (jsonb_typeof(raw_ssm_names) = 'array'),
  resolution_evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(resolution_evidence) = 'object'),
  resolved_at timestamptz not null default now(),
  primary key (representative_id, snapshot_id)
);

create table public.customer_resolutions (
  customer_id text not null check (customer_id ~ '^500[0-9]+$'),
  snapshot_id uuid not null references public.customer_master_snapshots(id),
  status public.customer_status not null,
  status_resolution_state text not null check (status_resolution_state in ('RESOLVED', 'UNKNOWN_REVIEW')),
  channel public.customer_channel not null,
  channel_resolution_state text not null check (channel_resolution_state in ('RESOLVED', 'CHANNEL_CONFLICT', 'UNKNOWN')),
  customer_name text,
  customer_name_resolution_state text not null check (customer_name_resolution_state in ('RESOLVED', 'CONFLICT_REVIEW', 'UNRESOLVED')),
  trade_name text,
  trade_name_resolution_state text not null check (trade_name_resolution_state in ('RESOLVED', 'CONFLICT_REVIEW', 'UNRESOLVED')),
  segment text,
  segment_resolution_state text not null check (segment_resolution_state in ('RESOLVED', 'CONFLICT_REVIEW', 'UNRESOLVED')),
  representative_id uuid references public.customer_representatives(id),
  representative_resolution_state text not null check (representative_resolution_state in ('RESOLVED', 'UNRESOLVED', 'CONFLICTING')),
  ssm_resolution_state text not null check (ssm_resolution_state in ('RESOLVED', 'MANUAL_REVIEW', 'UNRESOLVED')),
  current_snapshot_state text not null check (current_snapshot_state in ('PRESENT_IN_CURRENT_MASTER', 'NOT_PRESENT_IN_CURRENT_MASTER')),
  financial_scope_state text not null default 'DEFERRED_PACKAGE_10' check (financial_scope_state in ('DEFERRED_PACKAGE_10', 'RESOLVED', 'BLOCKED')),
  sellout_fkns_eligible boolean not null default false,
  source_observation_ids jsonb not null default '[]'::jsonb check (jsonb_typeof(source_observation_ids) = 'array'),
  resolution_evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(resolution_evidence) = 'object'),
  resolved_at timestamptz not null default now(),
  primary key (snapshot_id, customer_id)
);

create table public.customers (
  customer_id text primary key check (customer_id ~ '^500[0-9]+$'),
  status public.customer_status not null,
  channel public.customer_channel not null,
  customer_name text,
  trade_name text,
  segment text,
  canonical_ssm text,
  ssm_resolution_state text not null default 'UNRESOLVED' check (ssm_resolution_state in ('RESOLVED', 'MANUAL_REVIEW', 'UNRESOLVED')),
  current_snapshot_state text not null check (current_snapshot_state in ('PRESENT_IN_CURRENT_MASTER', 'NOT_PRESENT_IN_CURRENT_MASTER')),
  active_snapshot_id uuid references public.customer_master_snapshots(id),
  current_resolution jsonb not null check (jsonb_typeof(current_resolution) = 'object'),
  updated_at timestamptz not null default now()
);

create index customer_master_observations_customer_idx on public.customer_master_observations(customer_id, snapshot_id);
create index customer_resolutions_snapshot_idx on public.customer_resolutions(snapshot_id, status, channel);
create index customers_status_channel_idx on public.customers(status, channel, customer_id);

alter table public.customer_master_snapshots enable row level security;
alter table public.customer_master_observations enable row level security;
alter table public.customer_representatives enable row level security;
alter table public.customer_representative_ssm_resolutions enable row level security;
alter table public.customer_resolutions enable row level security;
alter table public.customers enable row level security;

create policy customer_master_snapshots_read on public.customer_master_snapshots for select to authenticated using (true);
create policy customer_master_observations_read on public.customer_master_observations for select to authenticated using (true);
create policy customer_representatives_read on public.customer_representatives for select to authenticated using (true);
create policy customer_representative_ssm_resolutions_read on public.customer_representative_ssm_resolutions for select to authenticated using (true);
create policy customer_resolutions_read on public.customer_resolutions for select to authenticated using (true);
create policy customers_read on public.customers for select to authenticated using (true);
grant select on public.customer_master_snapshots, public.customer_master_observations, public.customer_representatives, public.customer_representative_ssm_resolutions, public.customer_resolutions, public.customers to authenticated;

create or replace function public.assert_customer_master_publication_lineage(p_batch_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_publication_id uuid;
begin
  select p.id into v_publication_id
  from public.import_batches b
  join public.source_contract_versions sc on sc.id = b.source_contract_version_id
  join public.validation_runs vr on vr.id = b.validation_run_id
  join public.import_reconciliations ir on ir.id = b.reconciliation_id
  join public.publications p on p.id = b.published_publication_id
  join public.candidate_publications cp on cp.id = p.candidate_id
  where b.id = p_batch_id
    and b.source_kind = 'CUSTOMER_MASTER'
    and sc.source_kind = b.source_kind
    and b.source_verified_at is not null
    and b.status = 'PUBLISHED'
    and vr.batch_id = b.id
    and vr.contract_version_id = b.source_contract_version_id
    and vr.status = 'PASSED'
    and not exists (select 1 from public.validation_issues vi where vi.validation_run_id = vr.id and vi.severity = 'BLOCKING')
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
    raise exception 'CUSTOMER_MASTER batch must have a source-verified, same-batch validated, reconciled and published Package 01 lineage' using errcode = '22023';
  end if;
  return v_publication_id;
end;
$$;

create or replace function public.create_customer_master_snapshot(p_batch_id uuid, p_snapshot_key text, p_is_complete boolean default true)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid; v_as_of_at timestamptz;
begin
  perform public.assert_import_admin();
  perform public.assert_customer_master_publication_lineage(p_batch_id);
  select source_verified_at into v_as_of_at from public.import_batches where id = p_batch_id;
  insert into public.customer_master_snapshots(batch_id, snapshot_key, is_complete, as_of_at, as_of_source, created_by) values (p_batch_id, p_snapshot_key, p_is_complete, v_as_of_at, 'UPLOAD_TIME_FALLBACK', auth.uid()) returning id into v_id;
  return v_id;
end;
$$;

-- Narrow source-bound Package 01 adapter: map authoritative VALID staging rows set-wise; never perform row-by-row requests.
create or replace function public.stage_customer_master_rows(p_snapshot_id uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_count bigint; v_batch_id uuid;
begin
  perform public.assert_import_admin();
  select batch_id into v_batch_id from public.customer_master_snapshots where id = p_snapshot_id;
  if v_batch_id is null then raise exception 'Customer Master snapshot was not found' using errcode = 'P0002'; end if;
  perform public.assert_customer_master_publication_lineage(v_batch_id);
  if exists (
    select 1
    from public.customer_master_observations o
    join public.staging_rows s on s.id = o.source_staging_row_id
    where o.snapshot_id = p_snapshot_id
      and s.batch_id = v_batch_id
      and o.source_payload_hash <> s.payload_hash
  ) then raise exception 'Package 01 source payload changed for an existing Package 02 observation' using errcode = '23514'; end if;
  insert into public.customer_master_observations(snapshot_id, source_row_no, customer_id, customer_name, trade_name, raw_status, raw_channel, segment, raw_representative, raw_ssm, raw_payload, source_staging_row_id, source_payload_hash)
  select p_snapshot_id, s.source_row_no,
    s.payload ->> 'Müşteri',
    s.payload ->> 'Müşteri Adı',
    s.payload ->> 'Tabela Adı',
    s.payload ->> 'Müşteri Durumu',
    s.payload ->> 'Satış Kanalı Tanımı',
    s.payload ->> 'Müşteri Hacim Segmenti',
    s.payload ->> 'Satış Temsilcisi Adı',
    s.payload ->> 'Dist Satış Şefi Adı',
    s.payload,
    s.id,
    s.payload_hash
  from public.staging_rows s
  where s.batch_id = v_batch_id
    and s.row_status = 'VALID'
    and (s.payload ->> 'Müşteri') ~ '^500[0-9]+$'
  on conflict (snapshot_id, source_row_no) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;

create or replace function public.resolve_customer_master_snapshot(p_snapshot_id uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_count bigint; v_current uuid;
begin
  perform public.assert_import_admin();
  perform public.assert_customer_master_publication_lineage((select batch_id from public.customer_master_snapshots where id = p_snapshot_id));
  if not exists (select 1 from public.customer_master_snapshots where id = p_snapshot_id and is_complete) then raise exception 'Complete Customer Master snapshot was not found' using errcode = 'P0002'; end if;
  update public.customer_master_snapshots s set publication_id=b.published_publication_id
  from public.import_batches b where b.id=s.batch_id and s.id=p_snapshot_id;
  select id into v_current from public.customer_master_snapshots where is_complete order by as_of_at desc, created_at desc limit 1;
  insert into public.customer_representatives(normalized_name, raw_names)
  select lower(regexp_replace(trim(o.raw_representative), '\s+', ' ', 'g')), jsonb_agg(distinct to_jsonb(o.raw_representative))
  from public.customer_master_observations o where o.snapshot_id=p_snapshot_id and nullif(trim(o.raw_representative),'') is not null
  group by lower(regexp_replace(trim(o.raw_representative), '\s+', ' ', 'g'))
  on conflict (normalized_name) do update set raw_names=excluded.raw_names, updated_at=now();
  delete from public.customer_resolutions where snapshot_id=p_snapshot_id;
  insert into public.customer_resolutions(customer_id,snapshot_id,status,status_resolution_state,channel,channel_resolution_state,customer_name,customer_name_resolution_state,trade_name,trade_name_resolution_state,segment,segment_resolution_state,representative_id,representative_resolution_state,ssm_resolution_state,current_snapshot_state,financial_scope_state,sellout_fkns_eligible,source_observation_ids,resolution_evidence)
  with g as (
    select o.customer_id, array_agg(o.id order by o.source_row_no) ids,
      bool_or(lower(replace(trim(coalesce(o.raw_status,'')),'İ','i'))='aktif') active_seen,
      bool_or(lower(replace(trim(coalesce(o.raw_status,'')),'İ','i'))='pasif') passive_seen,
      bool_and(lower(replace(trim(coalesce(o.raw_status,'')),'İ','i')) in ('iptal','cancelled','canceled')) cancelled_only,
      bool_or(lower(replace(trim(coalesce(o.raw_status,'')),'İ','i')) not in ('aktif','pasif','iptal','cancelled','canceled')) unknown_seen,
      array_agg(distinct nullif(trim(o.raw_channel),'')) filter (where nullif(trim(o.raw_channel),'') is not null) channels,
      bool_or(trim(coalesce(o.raw_channel,'')) in ('Standart Açık','Horeca','Otel')) open_channel_seen,
      bool_or(trim(coalesce(o.raw_channel,'')) in ('Standart Kapalı','Ekomini')) closed_channel_seen,
      array_agg(distinct nullif(trim(o.customer_name),'') order by nullif(trim(o.customer_name),'')) filter (where nullif(trim(o.customer_name),'') is not null) names,
      array_agg(distinct nullif(trim(o.trade_name),'') order by nullif(trim(o.trade_name),'')) filter (where nullif(trim(o.trade_name),'') is not null) trades,
      array_agg(distinct nullif(trim(o.segment),'') order by nullif(trim(o.segment),'')) filter (where nullif(trim(o.segment),'') is not null) segments,
      array_agg(distinct lower(regexp_replace(trim(o.raw_representative),'\s+',' ','g'))) filter (where nullif(trim(o.raw_representative),'') is not null) reps,
      array_agg(distinct lower(regexp_replace(trim(o.raw_ssm),'\s+',' ','g'))) filter (where nullif(trim(o.raw_ssm),'') is not null) ssms
    from public.customer_master_observations o where o.snapshot_id=p_snapshot_id group by o.customer_id
  ), r as (
    select g.*, cr.id representative_id,
      case when cardinality(g.reps)=1 then 'RESOLVED' when cardinality(g.reps)=0 then 'UNRESOLVED' else 'CONFLICTING' end rep_state,
      case when g.active_seen then 'ACTIVE'::public.customer_status when g.passive_seen then 'PASSIVE'::public.customer_status when g.cancelled_only and not g.unknown_seen then 'CANCELLED'::public.customer_status else 'UNKNOWN'::public.customer_status end status_value,
      case when g.open_channel_seen and not g.closed_channel_seen then 'OPEN'::public.customer_channel when g.closed_channel_seen and not g.open_channel_seen then 'CLOSED'::public.customer_channel else 'UNCLASSIFIED'::public.customer_channel end channel_value,
      case when g.open_channel_seen and g.closed_channel_seen then 'CHANNEL_CONFLICT' else case when g.open_channel_seen or g.closed_channel_seen then 'RESOLVED' else 'UNKNOWN' end end channel_state,
      case when cardinality(g.names)=1 then g.names[1] end canonical_name,
      case when cardinality(g.names)=1 then 'RESOLVED' when cardinality(g.names)>1 then 'CONFLICT_REVIEW' else 'UNRESOLVED' end name_state,
      case when cardinality(g.trades)=1 then g.trades[1] end canonical_trade,
      case when cardinality(g.trades)=1 then 'RESOLVED' when cardinality(g.trades)>1 then 'CONFLICT_REVIEW' else 'UNRESOLVED' end trade_state,
      case when cardinality(g.segments)=1 then g.segments[1] end canonical_segment,
      case when cardinality(g.segments)=1 then 'RESOLVED' when cardinality(g.segments)>1 then 'CONFLICT_REVIEW' else 'UNRESOLVED' end segment_state
    from g left join public.customer_representatives cr on cr.normalized_name=g.reps[1]
  )
  select customer_id,p_snapshot_id,status_value,case when status_value='UNKNOWN' then 'UNKNOWN_REVIEW' else 'RESOLVED' end,channel_value,channel_state,canonical_name,name_state,canonical_trade,trade_state,canonical_segment,segment_state,representative_id,rep_state,'UNRESOLVED',case when p_snapshot_id=v_current then 'PRESENT_IN_CURRENT_MASTER' else 'NOT_PRESENT_IN_CURRENT_MASTER' end,'DEFERRED_PACKAGE_10',status_value='ACTIVE',to_jsonb(ids),jsonb_build_object('raw_channels',channels,'raw_representatives',reps,'raw_ssm_candidates',ssms,'customer_name_candidates',names,'trade_name_candidates',trades,'segment_candidates',segments,'financial_scope_state','DEFERRED_PACKAGE_10') from r;
  get diagnostics v_count = row_count;
  update public.customer_resolutions cr set current_snapshot_state=case when cr.snapshot_id=v_current then 'PRESENT_IN_CURRENT_MASTER' else 'NOT_PRESENT_IN_CURRENT_MASTER' end;
  if p_snapshot_id=v_current then
    insert into public.customers(customer_id,status,channel,customer_name,trade_name,segment,canonical_ssm,current_snapshot_state,active_snapshot_id,current_resolution)
    select cr.customer_id,cr.status,cr.channel,cr.customer_name,cr.trade_name,cr.segment,null,cr.current_snapshot_state,cr.snapshot_id,jsonb_build_object('snapshot_id',cr.snapshot_id,'status',cr.status,'channel',cr.channel,'customer_name',cr.customer_name,'customer_name_resolution_state',cr.customer_name_resolution_state,'trade_name',cr.trade_name,'trade_name_resolution_state',cr.trade_name_resolution_state,'segment',cr.segment,'segment_resolution_state',cr.segment_resolution_state,'representative_id',cr.representative_id,'representative_resolution_state',cr.representative_resolution_state,'canonical_ssm',null,'ssm_resolution_state',cr.ssm_resolution_state,'financial_scope_state',cr.financial_scope_state,'sellout_fkns_eligible',cr.sellout_fkns_eligible,'evidence',cr.resolution_evidence) from public.customer_resolutions cr where cr.snapshot_id=p_snapshot_id
    on conflict (customer_id) do update set status=excluded.status,channel=excluded.channel,customer_name=excluded.customer_name,trade_name=excluded.trade_name,segment=excluded.segment,canonical_ssm=excluded.canonical_ssm,current_snapshot_state=excluded.current_snapshot_state,active_snapshot_id=excluded.active_snapshot_id,current_resolution=excluded.current_resolution,updated_at=now();
    update public.customers c set current_snapshot_state=case when exists (select 1 from public.customer_resolutions cr where cr.snapshot_id=v_current and cr.customer_id=c.customer_id) then 'PRESENT_IN_CURRENT_MASTER' else 'NOT_PRESENT_IN_CURRENT_MASTER' end;
  end if;
  return v_count;
end;
$$;

create or replace function public.resolve_representative_ssm(p_representative text, p_snapshot_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_known bigint; v_max bigint; v_distinct bigint; v_ssm text; v_ratio numeric(8,6); v_state text; v_current uuid; v_name text:=lower(regexp_replace(trim(p_representative),'\s+',' ','g')); v_evidence jsonb;
begin
  perform public.assert_import_admin();
  if not exists (select 1 from public.customer_master_snapshots where id=p_snapshot_id) then raise exception 'SSM resolution snapshot was not found' using errcode = 'P0002'; end if;
  select id into v_current from public.customer_master_snapshots where is_complete order by as_of_at desc, created_at desc limit 1;
  select count(distinct o.customer_id) into v_known from public.customer_master_observations o join public.customer_resolutions c on c.customer_id=o.customer_id and c.snapshot_id=o.snapshot_id where o.snapshot_id=p_snapshot_id and c.status='ACTIVE' and lower(regexp_replace(trim(o.raw_representative),'\s+',' ','g'))=v_name and nullif(trim(o.raw_ssm),'') is not null;
  if v_known=0 then v_state:='UNRESOLVED'; v_ratio:=0;
  else
    select max(n), count(*) filter (where n=(select max(n) from (select count(distinct o.customer_id) n from public.customer_master_observations o join public.customer_resolutions c on c.customer_id=o.customer_id and c.snapshot_id=o.snapshot_id where o.snapshot_id=p_snapshot_id and c.status='ACTIVE' and lower(regexp_replace(trim(o.raw_representative),'\s+',' ','g'))=v_name and nullif(trim(o.raw_ssm),'') is not null group by lower(regexp_replace(trim(o.raw_ssm),'\s+',' ','g'))) z)) into v_max,v_distinct from (select count(distinct o.customer_id) n from public.customer_master_observations o join public.customer_resolutions c on c.customer_id=o.customer_id and c.snapshot_id=o.snapshot_id where o.snapshot_id=p_snapshot_id and c.status='ACTIVE' and lower(regexp_replace(trim(o.raw_representative),'\s+',' ','g'))=v_name and nullif(trim(o.raw_ssm),'') is not null group by lower(regexp_replace(trim(o.raw_ssm),'\s+',' ','g'))) q;
    v_ratio:=v_max::numeric/v_known;
    if v_distinct=1 and v_ratio>=.9 then select min(raw_ssm) into v_ssm from public.customer_master_observations o join public.customer_resolutions c on c.customer_id=o.customer_id and c.snapshot_id=o.snapshot_id where o.snapshot_id=p_snapshot_id and c.status='ACTIVE' and lower(regexp_replace(trim(o.raw_representative),'\s+',' ','g'))=v_name and nullif(trim(o.raw_ssm),'') is not null group by lower(regexp_replace(trim(o.raw_ssm),'\s+',' ','g')) order by count(distinct o.customer_id) desc limit 1; v_state:='RESOLVED'; else v_state:='MANUAL_REVIEW'; end if;
  end if;
  v_evidence:=jsonb_build_object('snapshot_id',p_snapshot_id,'representative',p_representative,'normalized_representative',v_name,'canonical_ssm',v_ssm,'state',v_state,'dominant_ratio',v_ratio,'known_active_count',v_known);
  insert into public.customer_representative_ssm_resolutions(representative_id,snapshot_id,canonical_ssm,resolution_state,dominant_ratio,known_active_count,raw_ssm_names,resolution_evidence)
  select cr.id,p_snapshot_id,v_ssm,v_state,v_ratio,v_known,coalesce((select jsonb_agg(distinct o.raw_ssm) from public.customer_master_observations o where o.snapshot_id=p_snapshot_id and lower(regexp_replace(trim(o.raw_representative),'\s+',' ','g'))=v_name and nullif(trim(o.raw_ssm),'') is not null),'[]'::jsonb),v_evidence
  from public.customer_representatives cr where cr.normalized_name=v_name
  on conflict (representative_id,snapshot_id) do update set canonical_ssm=excluded.canonical_ssm,resolution_state=excluded.resolution_state,dominant_ratio=excluded.dominant_ratio,known_active_count=excluded.known_active_count,raw_ssm_names=excluded.raw_ssm_names,resolution_evidence=excluded.resolution_evidence,resolved_at=now();
  update public.customer_resolutions cr set ssm_resolution_state=v_state, resolution_evidence=resolution_evidence || jsonb_build_object('ssm_resolution',v_evidence) where cr.snapshot_id=p_snapshot_id and cr.representative_id=(select id from public.customer_representatives where normalized_name=v_name);
  if p_snapshot_id=v_current then
    update public.customer_representatives set ssm_resolution_state=v_state,canonical_ssm=v_ssm,dominant_ratio=v_ratio,raw_ssm_names=coalesce((select jsonb_agg(distinct o.raw_ssm) from public.customer_master_observations o where o.snapshot_id=p_snapshot_id and lower(regexp_replace(trim(o.raw_representative),'\s+',' ','g'))=v_name and nullif(trim(o.raw_ssm),'') is not null),'[]'::jsonb),updated_at=now() where normalized_name=v_name;
    update public.customers c set canonical_ssm=v_ssm,ssm_resolution_state=v_state,current_resolution=current_resolution || jsonb_build_object('canonical_ssm',v_ssm,'ssm_resolution_state',v_state,'ssm_evidence',v_evidence) where c.active_snapshot_id=p_snapshot_id;
  end if;
  return jsonb_build_object('state',v_state,'canonical_ssm',v_ssm,'dominant_ratio',v_ratio,'known_active_count',v_known);
end;
$$;

revoke all on function public.create_customer_master_snapshot(uuid,text,boolean) from public;
revoke all on function public.stage_customer_master_rows(uuid) from public;
revoke all on function public.resolve_customer_master_snapshot(uuid) from public;
revoke all on function public.resolve_representative_ssm(text,uuid) from public;
revoke all on function public.assert_customer_master_publication_lineage(uuid) from public, authenticated;
grant execute on function public.create_customer_master_snapshot(uuid,text,boolean), public.stage_customer_master_rows(uuid), public.resolve_customer_master_snapshot(uuid), public.resolve_representative_ssm(text,uuid) to authenticated;
