-- Package 02: align CUSTOMER_MASTER validation and status semantics with the real export.

do $$
declare
  v_v3 public.source_contract_versions;
  v_v3_count integer;
begin
  select count(*) into v_v3_count
  from public.source_contract_versions
  where source_kind = 'CUSTOMER_MASTER' and version = '3';
  if v_v3_count <> 1 then
    raise exception 'CUSTOMER_MASTER version 3 guard failed: expected exactly one row, found %', v_v3_count;
  end if;

  select * into v_v3
  from public.source_contract_versions
  where source_kind = 'CUSTOMER_MASTER' and version = '3';

  if v_v3.created_by is not null
    or v_v3.is_active is distinct from true
    or v_v3.retired_at is not null
    or v_v3.required_sheet is distinct from 'SAPUI5 dışa aktarımı'
    or v_v3.required_headers is distinct from '["Müşteri","Müşteri Adı","Tabela Adı","Satış Temsilcisi Adı","Dist Satış Şefi Adı","Satış Kanalı Tanımı","Müşteri Hacim Segmenti","Müşteri Durumu"]'::jsonb
    or v_v3.required_fields is distinct from '["Müşteri","Müşteri Adı","Tabela Adı","Satış Temsilcisi Adı","Dist Satış Şefi Adı","Satış Kanalı Tanımı","Müşteri Hacim Segmenti","Müşteri Durumu"]'::jsonb
    or v_v3.control_total_fields is distinct from '{}'::jsonb
    or v_v3.control_total_scales is distinct from '{}'::jsonb
    or v_v3.publication_mode is distinct from 'FULL_REPLACE'::public.publication_mode then
    raise exception 'CUSTOMER_MASTER version 3 guard failed: definition or ownership differs from the known 00004 contract';
  end if;

  if exists (
    select 1
    from public.source_contract_versions
    where source_kind = 'CUSTOMER_MASTER'
      and is_active
      and id <> v_v3.id
  ) then
    raise exception 'CUSTOMER_MASTER version 3 guard failed: unexpected additional active CUSTOMER_MASTER contract exists';
  end if;

  if exists (
    select 1
    from public.import_batches b
    where b.source_contract_version_id = v_v3.id
      and (
        b.status is distinct from 'FAILED'::public.import_batch_status
        or b.published_publication_id is not null
        or exists (
          select 1
          from public.candidate_publications cp
          where cp.batch_id = b.id
        )
        or exists (
          select 1
          from public.publications p
          join public.candidate_publications cp
            on cp.id = p.candidate_id
          where cp.batch_id = b.id
        )
      )
  ) then
    raise exception 'CUSTOMER_MASTER version 3 guard failed: only failed batches without candidate/publication lineage may reference v3';
  end if;

  update public.source_contract_versions
  set is_active = false, retired_at = clock_timestamp()
  where id = v_v3.id;

  perform public.register_system_source_contract(
    'CUSTOMER_MASTER', '4', 'SAPUI5 dışa aktarımı',
    '["Müşteri","Müşteri Adı","Tabela Adı","Satış Temsilcisi Adı","Dist Satış Şefi Adı","Satış Kanalı Tanımı","Müşteri Hacim Segmenti","Müşteri Durumu"]'::jsonb,
    '["Müşteri"]'::jsonb,
    '{}'::jsonb, '{}'::jsonb, 'FULL_REPLACE'::public.publication_mode
  );
end;
$$;

create or replace function public.validate_import_batch(p_batch_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
set statement_timeout = '30s'
as $$
declare
  v_batch public.import_batches;
  v_contract public.source_contract_versions;
  v_run_id uuid;
begin
  perform public.assert_import_admin();
  select * into v_batch from public.import_batches where id = p_batch_id for update;
  if not found or v_batch.source_verified_at is null then
    raise exception 'Verified import batch is required' using errcode = '55000';
  end if;
  if v_batch.validation_run_id is not null then return v_batch.validation_run_id; end if;
  if v_batch.received_chunks <> v_batch.expected_chunks or v_batch.staged_rows <> v_batch.expected_rows then
    raise exception 'All expected chunks and rows must be staged before validation' using errcode = '55000';
  end if;
  select * into v_contract from public.source_contract_versions where id = v_batch.source_contract_version_id;
  with classified as (
    select
      s.id,
      case
        when coalesce(s.payload ->> '__exclude_reason', '') <> ''
          then 'EXCLUDED'::public.staging_row_status

        when row_number() over (
          partition by s.payload_hash
          order by s.source_row_no
        ) > 1
          then 'DUPLICATE'::public.staging_row_status

        when exists (
          select 1
          from jsonb_array_elements_text(v_contract.required_fields) field(name)
          where nullif(btrim(s.payload ->> field.name), '') is null
        )
          then 'BLOCKED'::public.staging_row_status

        when exists (
          select 1
          from jsonb_each_text(v_contract.control_total_fields) spec(metric, field_name)
          where coalesce(s.payload ->> spec.field_name, '')
            !~ '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$'
        )
          then 'BLOCKED'::public.staging_row_status

        else 'VALID'::public.staging_row_status
      end as row_status
    from public.staging_rows s
    where s.batch_id = p_batch_id
  )
  update public.staging_rows s
  set row_status = classified.row_status
  from classified
  where s.id = classified.id;
  insert into public.validation_runs (batch_id, contract_version_id, valid_rows, excluded_rows, blocked_rows, duplicate_rows, status)
  select p_batch_id, v_contract.id,
    count(*) filter (where row_status = 'VALID'), count(*) filter (where row_status = 'EXCLUDED'),
    count(*) filter (where row_status = 'BLOCKED'), count(*) filter (where row_status = 'DUPLICATE'),
    case when count(*) filter (where row_status = 'BLOCKED') = 0 then 'PASSED' else 'BLOCKED' end
  from public.staging_rows where batch_id = p_batch_id returning id into v_run_id;
  insert into public.validation_issues (validation_run_id, staging_row_id, severity, code, detail)
  select
    v_run_id,
    s.id,
    case s.row_status when 'BLOCKED' then 'BLOCKING' when 'DUPLICATE' then 'DUPLICATE' else 'EXCLUDED' end,
    case
      when s.row_status = 'BLOCKED' and missing_fields.fields is not null then 'MISSING_REQUIRED_FIELD'
      when s.row_status = 'BLOCKED' then 'INVALID_CONTROL_TOTAL_FIELD'
      when s.row_status = 'DUPLICATE' then 'DUPLICATE_PAYLOAD'
      else 'EXCLUDED_BY_SOURCE'
    end,
    jsonb_build_object(
      'source_row_no', s.source_row_no,
      'missing_required_fields', coalesce(missing_fields.fields, '[]'::jsonb),
      'invalid_control_total_fields', coalesce(invalid_controls.fields, '[]'::jsonb)
    )
  from public.staging_rows s
  left join lateral (
    select jsonb_agg(field.name order by field.name) as fields
    from jsonb_array_elements_text(v_contract.required_fields) field(name)
    where nullif(btrim(s.payload ->> field.name), '') is null
  ) missing_fields on true
  left join lateral (
    select jsonb_agg(spec.field_name order by spec.field_name) as fields
    from jsonb_each_text(v_contract.control_total_fields) spec(metric, field_name)
    where coalesce(s.payload ->> spec.field_name, '') !~ '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$'
  ) invalid_controls on true
  where s.batch_id = p_batch_id and s.row_status <> 'VALID';
  update public.import_batches set validation_run_id = v_run_id, status = 'VALIDATED' where id = p_batch_id;
  return v_run_id;
end;
$$;

create or replace function public.resolve_customer_master_snapshot(p_snapshot_id uuid)
returns bigint language plpgsql security definer set search_path = public as $$
declare v_count bigint; v_current uuid;
begin
  perform public.assert_import_admin();
  perform public.assert_customer_master_publication_lineage((select batch_id from public.customer_master_snapshots where id = p_snapshot_id));
  if not exists (select 1 from public.customer_master_snapshots where id = p_snapshot_id and is_complete) then raise exception 'Complete Customer Master snapshot was not found' using errcode = 'P0002'; end if;
  update public.customer_master_snapshots s set publication_id=b.published_publication_id from public.import_batches b where b.id=s.batch_id and s.id=p_snapshot_id;
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
      bool_or(lower(replace(trim(coalesce(o.raw_status,'')),'İ','i')) in ('aktif','aktif (a)')) active_seen,
      bool_or(lower(replace(trim(coalesce(o.raw_status,'')),'İ','i')) in ('pasif','pasif (p)')) passive_seen,
      bool_and(lower(replace(trim(coalesce(o.raw_status,'')),'İ','i')) in ('iptal','iptal (c)','cancelled','canceled')) cancelled_only,
      bool_or(lower(replace(trim(coalesce(o.raw_status,'')),'İ','i')) not in ('aktif','aktif (a)','pasif','pasif (p)','iptal','iptal (c)','cancelled','canceled')) unknown_seen,
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

revoke all on function public.validate_import_batch(uuid) from public;
grant execute on function public.validate_import_batch(uuid) to authenticated;
revoke all on function public.resolve_customer_master_snapshot(uuid) from public;
grant execute on function public.resolve_customer_master_snapshot(uuid) to authenticated;
