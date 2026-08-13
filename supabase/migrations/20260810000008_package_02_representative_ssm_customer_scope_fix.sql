-- Package 02: keep representative-to-SSM materialization within the target
-- representative's resolved current-customer scope.

create or replace function public.resolve_representative_ssm(p_representative text, p_snapshot_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_known bigint;
  v_max bigint;
  v_distinct bigint;
  v_ssm text;
  v_ratio numeric(8,6);
  v_state text;
  v_current uuid;
  v_representative_id uuid;
  v_name text := lower(regexp_replace(trim(p_representative),'\s+',' ','g'));
  v_evidence jsonb;
  v_raw_ssm_names jsonb;
begin
  perform public.assert_import_admin();
  if not exists (select 1 from public.customer_master_snapshots where id = p_snapshot_id) then
    raise exception 'SSM resolution snapshot was not found' using errcode = 'P0002';
  end if;

  select id into v_current
  from public.customer_master_snapshots
  where is_complete
  order by as_of_at desc, created_at desc
  limit 1;

  select id into v_representative_id
  from public.customer_representatives
  where normalized_name = v_name;

  select count(distinct o.customer_id) into v_known
  from public.customer_master_observations o
  join public.customer_resolutions c
    on c.customer_id = o.customer_id
   and c.snapshot_id = o.snapshot_id
  where o.snapshot_id = p_snapshot_id
    and c.status = 'ACTIVE'
    and lower(regexp_replace(trim(o.raw_representative),'\s+',' ','g')) = v_name
    and nullif(trim(o.raw_ssm),'') is not null;

  if v_known = 0 then
    v_state := 'UNRESOLVED';
    v_ratio := 0;
  else
    select max(n), count(*) filter (where n = (
      select max(n)
      from (
        select count(distinct o.customer_id) n
        from public.customer_master_observations o
        join public.customer_resolutions c
          on c.customer_id = o.customer_id
         and c.snapshot_id = o.snapshot_id
        where o.snapshot_id = p_snapshot_id
          and c.status = 'ACTIVE'
          and lower(regexp_replace(trim(o.raw_representative),'\s+',' ','g')) = v_name
          and nullif(trim(o.raw_ssm),'') is not null
        group by lower(regexp_replace(trim(o.raw_ssm),'\s+',' ','g'))
      ) z
    )) into v_max, v_distinct
    from (
      select count(distinct o.customer_id) n
      from public.customer_master_observations o
      join public.customer_resolutions c
        on c.customer_id = o.customer_id
       and c.snapshot_id = o.snapshot_id
      where o.snapshot_id = p_snapshot_id
        and c.status = 'ACTIVE'
        and lower(regexp_replace(trim(o.raw_representative),'\s+',' ','g')) = v_name
        and nullif(trim(o.raw_ssm),'') is not null
      group by lower(regexp_replace(trim(o.raw_ssm),'\s+',' ','g'))
    ) q;
    v_ratio := v_max::numeric / v_known;
    if v_distinct = 1 and v_ratio >= .9 then
      select min(raw_ssm) into v_ssm
      from public.customer_master_observations o
      join public.customer_resolutions c
        on c.customer_id = o.customer_id
       and c.snapshot_id = o.snapshot_id
      where o.snapshot_id = p_snapshot_id
        and c.status = 'ACTIVE'
        and lower(regexp_replace(trim(o.raw_representative),'\s+',' ','g')) = v_name
        and nullif(trim(o.raw_ssm),'') is not null
      group by lower(regexp_replace(trim(o.raw_ssm),'\s+',' ','g'))
      order by count(distinct o.customer_id) desc
      limit 1;
      v_state := 'RESOLVED';
    else
      v_state := 'MANUAL_REVIEW';
    end if;
  end if;

  select coalesce(jsonb_agg(distinct o.raw_ssm), '[]'::jsonb) into v_raw_ssm_names
  from public.customer_master_observations o
  where o.snapshot_id = p_snapshot_id
    and lower(regexp_replace(trim(o.raw_representative),'\s+',' ','g')) = v_name
    and nullif(trim(o.raw_ssm),'') is not null;

  v_evidence := jsonb_build_object(
    'snapshot_id', p_snapshot_id,
    'representative', p_representative,
    'normalized_representative', v_name,
    'canonical_ssm', v_ssm,
    'state', v_state,
    'dominant_ratio', v_ratio,
    'known_active_count', v_known
  );

  insert into public.customer_representative_ssm_resolutions(representative_id,snapshot_id,canonical_ssm,resolution_state,dominant_ratio,known_active_count,raw_ssm_names,resolution_evidence)
  select v_representative_id,p_snapshot_id,v_ssm,v_state,v_ratio,v_known,v_raw_ssm_names,v_evidence
  where v_representative_id is not null
  on conflict (representative_id,snapshot_id) do update
    set canonical_ssm = excluded.canonical_ssm,
        resolution_state = excluded.resolution_state,
        dominant_ratio = excluded.dominant_ratio,
        known_active_count = excluded.known_active_count,
        raw_ssm_names = excluded.raw_ssm_names,
        resolution_evidence = excluded.resolution_evidence,
        resolved_at = now();

  update public.customer_resolutions cr
  set ssm_resolution_state = v_state,
      resolution_evidence = resolution_evidence || jsonb_build_object('ssm_resolution',v_evidence)
  where cr.snapshot_id = p_snapshot_id
    and cr.representative_id = v_representative_id
    and cr.representative_resolution_state = 'RESOLVED';

  if p_snapshot_id = v_current then
    update public.customer_representatives
    set ssm_resolution_state = v_state,
        canonical_ssm = v_ssm,
        dominant_ratio = v_ratio,
        raw_ssm_names = v_raw_ssm_names,
        updated_at = now()
    where id = v_representative_id;

    update public.customers c
    set canonical_ssm = v_ssm,
        ssm_resolution_state = v_state,
        current_resolution = current_resolution || jsonb_build_object(
          'canonical_ssm', v_ssm,
          'ssm_resolution_state', v_state,
          'ssm_evidence', v_evidence
        )
    from public.customer_resolutions cr
    where c.customer_id = cr.customer_id
      and c.active_snapshot_id = p_snapshot_id
      and cr.snapshot_id = p_snapshot_id
      and cr.representative_id = v_representative_id
      and cr.representative_resolution_state = 'RESOLVED';
  end if;

  return jsonb_build_object('state',v_state,'canonical_ssm',v_ssm,'dominant_ratio',v_ratio,'known_active_count',v_known);
end;
$$;

revoke all on function public.resolve_representative_ssm(text,uuid) from public;
grant execute on function public.resolve_representative_ssm(text,uuid) to authenticated;
