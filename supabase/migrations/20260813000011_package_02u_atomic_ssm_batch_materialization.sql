-- Package 02U: execute the existing SSM resolver set atomically and assert the release contract before commit.

create or replace function public.resolve_representative_ssm_batch(
  p_representatives text[],
  p_snapshot_id uuid
)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_input_names text[];
  v_input_count bigint;
  v_result jsonb;
  v_results jsonb := '[]'::jsonb;
  v_non_null bigint;
  v_null bigint;
  v_mertcan bigint;
  v_ugur bigint;
  v_yusuf bigint;
  v_other_non_null bigint;
  v_non_active_writes bigint;
  v_authoritative_mismatch bigint;
  v_cross_rep_mismatch bigint;
  v_observations bigint;
  v_customers bigint;
  v_batch_status text;
  v_snapshot_complete boolean;
  v_representative text;
begin
  perform public.assert_import_admin();

  if p_representatives is null or cardinality(p_representatives) = 0 then
    raise exception 'SSM batch requires a non-empty representative array' using errcode = '22023';
  end if;
  if exists (select 1 from unnest(p_representatives) as input(name) where nullif(trim(input.name), '') is null) then
    raise exception 'SSM batch representatives cannot contain NULL or empty names' using errcode = '22023';
  end if;

  select array_agg(lower(regexp_replace(trim(input.name), '\s+', ' ', 'g')) order by input.ordinality)
    into v_input_names
  from unnest(p_representatives) with ordinality as input(name, ordinality);
  v_input_count := cardinality(v_input_names);
  if v_input_count <> (select count(distinct name) from unnest(v_input_names) as input(name)) then
    raise exception 'SSM batch representatives must be unique' using errcode = '22023';
  end if;

  foreach v_representative in array p_representatives loop
    v_result := public.resolve_representative_ssm(v_representative, p_snapshot_id);
    v_results := v_results || jsonb_build_array(jsonb_build_object('representative', v_representative, 'result', v_result));
  end loop;

  if v_input_count <> 9 then
    raise exception 'SSM batch assertion failed: input distinct representatives = %, expected 9', v_input_count using errcode = '23514';
  end if;

  select count(*) filter (where c.canonical_ssm is not null),
         count(*) filter (where c.canonical_ssm is null)
    into v_non_null, v_null
  from public.customers c
  where c.active_snapshot_id = p_snapshot_id;
  if v_non_null <> 1195 or v_null <> 586 then
    raise exception 'SSM batch assertion failed: canonical_ssm non-null=% null=% expected 1195/586', v_non_null, v_null using errcode = '23514';
  end if;

  select count(*) filter (where upper(trim(c.canonical_ssm)) = 'MERTCAN ÇİNAR'),
         count(*) filter (where upper(trim(c.canonical_ssm)) = 'UĞUR ERGON'),
         count(*) filter (where upper(trim(c.canonical_ssm)) = 'YUSUF AKDOĞAN'),
         count(*) filter (where c.canonical_ssm is not null and upper(trim(c.canonical_ssm)) not in ('MERTCAN ÇİNAR', 'UĞUR ERGON', 'YUSUF AKDOĞAN'))
    into v_mertcan, v_ugur, v_yusuf, v_other_non_null
  from public.customers c
  where c.active_snapshot_id = p_snapshot_id;
  if v_mertcan <> 508 or v_ugur <> 275 or v_yusuf <> 412 then
    raise exception 'SSM batch assertion failed: SSM counts MERTCAN=% UĞUR=% YUSUF=% expected 508/275/412', v_mertcan, v_ugur, v_yusuf using errcode = '23514';
  end if;
  if v_other_non_null <> 0 then
    raise exception 'SSM batch assertion failed: other non-null canonical SSM=% expected 0', v_other_non_null using errcode = '23514';
  end if;

  select count(*) into v_non_active_writes
  from public.customers c
  join public.customer_resolutions cr on cr.customer_id = c.customer_id and cr.snapshot_id = p_snapshot_id
  join public.customer_representatives r on r.id = cr.representative_id
  where c.active_snapshot_id = p_snapshot_id
    and cr.status <> 'ACTIVE'
    and r.normalized_name = any(v_input_names)
    and c.canonical_ssm is not null;
  if v_non_active_writes <> 0 then
    raise exception 'SSM batch assertion failed: non-ACTIVE same-representative writes=% expected 0', v_non_active_writes using errcode = '23514';
  end if;

  select count(*) into v_authoritative_mismatch
  from public.customers c
  join public.customer_resolutions cr on cr.customer_id = c.customer_id and cr.snapshot_id = p_snapshot_id
  join public.customer_representatives r on r.id = cr.representative_id
  left join public.customer_representative_ssm_resolutions rs on rs.representative_id = cr.representative_id and rs.snapshot_id = p_snapshot_id
  where c.active_snapshot_id = p_snapshot_id
    and c.canonical_ssm is not null
    and r.normalized_name = any(v_input_names)
    and rtrim(coalesce(rs.canonical_ssm, '')) is distinct from rtrim(c.canonical_ssm);
  if v_authoritative_mismatch <> 0 then
    raise exception 'SSM batch assertion failed: authoritative leakage mismatch=% expected 0', v_authoritative_mismatch using errcode = '23514';
  end if;

  select count(*) into v_cross_rep_mismatch
  from public.customers c
  join public.customer_resolutions cr on cr.customer_id = c.customer_id and cr.snapshot_id = p_snapshot_id
  join public.customer_representatives r on r.id = cr.representative_id
  where c.active_snapshot_id = p_snapshot_id
    and c.canonical_ssm is not null
    and r.canonical_ssm is distinct from c.canonical_ssm;
  if v_cross_rep_mismatch <> 0 then
    raise exception 'SSM batch assertion failed: cross-representative mismatch=% expected 0', v_cross_rep_mismatch using errcode = '23514';
  end if;

  select count(*) into v_observations from public.customer_master_observations where snapshot_id = p_snapshot_id;
  select count(*) into v_customers from public.customers where active_snapshot_id = p_snapshot_id;
  select b.status::text, s.is_complete into v_batch_status, v_snapshot_complete
  from public.customer_master_snapshots s join public.import_batches b on b.id = s.batch_id
  where s.id = p_snapshot_id;
  if v_observations <> 3559 or v_customers <> 1781 then
    raise exception 'SSM batch assertion failed: observations=% customers=% expected 3559/1781', v_observations, v_customers using errcode = '23514';
  end if;
  if v_batch_status <> 'PUBLISHED' or v_snapshot_complete is distinct from true then
    raise exception 'SSM batch assertion failed: batch=% snapshot_complete=% expected PUBLISHED/true', v_batch_status, v_snapshot_complete using errcode = '23514';
  end if;

  return jsonb_build_object(
    'representative_count', v_input_count,
    'results', v_results,
    'canonical_ssm_non_null', v_non_null,
    'canonical_ssm_null', v_null,
    'mertcan_cinar', v_mertcan,
    'ugur_ergon', v_ugur,
    'yusuf_akdogan', v_yusuf,
    'other_non_null_canonical_ssm', v_other_non_null,
    'non_active_same_representative_writes', v_non_active_writes,
    'authoritative_leakage_mismatch', v_authoritative_mismatch,
    'cross_representative_mismatch', v_cross_rep_mismatch,
    'observations', v_observations,
    'customers', v_customers,
    'batch_status', v_batch_status,
    'snapshot_complete', v_snapshot_complete
  );
end;
$$;

revoke all on function public.resolve_representative_ssm_batch(text[], uuid) from public, anon, authenticated;
grant execute on function public.resolve_representative_ssm_batch(text[], uuid) to authenticated;
