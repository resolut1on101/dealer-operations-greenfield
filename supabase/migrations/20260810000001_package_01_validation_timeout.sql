-- Package 01 validation performance remediation.
-- Keep validation semantics unchanged while avoiding repeated row-status scans.

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
  if v_batch.validation_run_id is not null then
    return v_batch.validation_run_id;
  end if;
  if v_batch.received_chunks <> v_batch.expected_chunks or v_batch.staged_rows <> v_batch.expected_rows then
    raise exception 'All expected chunks and rows must be staged before validation' using errcode = '55000';
  end if;
  select * into v_contract from public.source_contract_versions where id = v_batch.source_contract_version_id;

  with classified as (
    select
      s.id,
      case
        when coalesce(s.payload ->> '__exclude_reason', '') <> '' then 'EXCLUDED'::public.staging_row_status
        when row_number() over (partition by s.payload_hash order by s.source_row_no) > 1 then 'DUPLICATE'::public.staging_row_status
        when exists (
          select 1
          from jsonb_array_elements_text(v_contract.required_fields) field(name)
          where nullif(btrim(s.payload ->> field.name), '') is null
        ) then 'BLOCKED'::public.staging_row_status
        when exists (
          select 1
          from jsonb_each_text(v_contract.control_total_fields) spec(metric, field_name)
          where coalesce(s.payload ->> spec.field_name, '') !~ '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$'
        ) then 'BLOCKED'::public.staging_row_status
        else 'VALID'::public.staging_row_status
      end as row_status
    from public.staging_rows s
    where s.batch_id = p_batch_id
  )
  update public.staging_rows s
  set row_status = classified.row_status
  from classified
  where s.id = classified.id;

  insert into public.validation_runs (
    batch_id, contract_version_id, valid_rows, excluded_rows, blocked_rows, duplicate_rows, status
  )
  select
    p_batch_id,
    v_contract.id,
    count(*) filter (where row_status = 'VALID'),
    count(*) filter (where row_status = 'EXCLUDED'),
    count(*) filter (where row_status = 'BLOCKED'),
    count(*) filter (where row_status = 'DUPLICATE'),
    case when count(*) filter (where row_status = 'BLOCKED') = 0 then 'PASSED' else 'BLOCKED' end
  from public.staging_rows
  where batch_id = p_batch_id
  returning id into v_run_id;

  insert into public.validation_issues (validation_run_id, staging_row_id, severity, code, detail)
  select
    v_run_id,
    s.id,
    case s.row_status when 'BLOCKED' then 'BLOCKING' when 'DUPLICATE' then 'DUPLICATE' else 'EXCLUDED' end,
    case s.row_status when 'BLOCKED' then 'MISSING_REQUIRED_FIELD' when 'DUPLICATE' then 'DUPLICATE_PAYLOAD' else 'EXCLUDED_BY_SOURCE' end,
    jsonb_build_object('source_row_no', s.source_row_no)
  from public.staging_rows s
  where s.batch_id = p_batch_id and s.row_status <> 'VALID';

  update public.import_batches
  set validation_run_id = v_run_id, status = 'VALIDATED'
  where id = p_batch_id;
  return v_run_id;
end;
$$;

grant execute on function public.validate_import_batch(uuid) to authenticated;
