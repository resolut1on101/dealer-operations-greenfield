-- Package 01 reconciliation precision remediation.
-- Contract scales are authoritative; reconciliation remains exact after canonicalization.

alter table public.source_contract_versions
  add column if not exists control_total_scales jsonb not null default '{}'::jsonb;

update public.source_contract_versions
set control_total_scales = (
  select coalesce(jsonb_object_agg(metric, case when metric ilike '%lt%' then 2 else 0 end), '{}'::jsonb)
  from jsonb_object_keys(control_total_fields) as metric
)
where control_total_scales = '{}'::jsonb;

create or replace function public.validate_control_total_scales(p_fields jsonb, p_scales jsonb)
returns void language plpgsql immutable strict set search_path = public as $$
declare v_key text; v_scale numeric;
begin
  if jsonb_typeof(p_fields) <> 'object' or jsonb_typeof(p_scales) <> 'object' then
    raise exception 'Control-total fields and scales must be JSON objects' using errcode = '22023';
  end if;
  if exists (select 1 from jsonb_object_keys(p_fields) as field where not (p_scales ? field))
    or exists (select 1 from jsonb_object_keys(p_scales) as field where not (p_fields ? field)) then
    raise exception 'Every control-total field must have exactly one canonical scale' using errcode = '22023';
  end if;
  for v_key, v_scale in select key, (value #>> '{}')::numeric from jsonb_each(p_scales) loop
    if jsonb_typeof(p_scales -> v_key) <> 'number' or v_scale < 0 or v_scale > 18 or v_scale <> trunc(v_scale) then
      raise exception 'Control-total scale must be an integer from 0 to 18' using errcode = '22023';
    end if;
  end loop;
end;
$$;

create or replace function public.canonical_control_totals(p_totals jsonb, p_scales jsonb)
returns jsonb language plpgsql immutable strict set search_path = public as $$
declare v_key text; v_value jsonb; v_scale integer; v_output jsonb := '{}'::jsonb;
begin
  if jsonb_typeof(p_totals) <> 'object' then
    raise exception 'Control totals must be a JSON object' using errcode = '22023';
  end if;
  for v_key, v_value in select key, value from jsonb_each(p_totals) loop
    if not (p_scales ? v_key) or jsonb_typeof(v_value) not in ('number', 'string')
      or nullif(btrim(v_value #>> '{}'), '') is null then
      raise exception 'Control total % has no valid canonical value or scale', v_key using errcode = '22023';
    end if;
    v_scale := ((p_scales -> v_key) #>> '{}')::integer;
    v_output := v_output || jsonb_build_object(v_key, to_jsonb(round((v_value #>> '{}')::numeric, v_scale)));
  end loop;
  return v_output;
end;
$$;

create or replace function public.prevent_used_source_contract_mutation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.import_batches where source_contract_version_id = old.id)
    and (new.source_kind, new.version, new.required_sheet, new.required_headers, new.required_fields,
         new.control_total_fields, new.control_total_scales, new.publication_mode)
      is distinct from
        (old.source_kind, old.version, old.required_sheet, old.required_headers, old.required_fields,
         old.control_total_fields, old.control_total_scales, old.publication_mode) then
    raise exception 'A source contract definition cannot change after an import batch uses it' using errcode = '55000';
  end if;
  return new;
end;
$$;

create or replace function public.register_source_contract(
  p_source_kind text, p_version text, p_required_sheet text, p_required_headers jsonb,
  p_required_fields jsonb, p_control_total_fields jsonb, p_control_total_scales jsonb,
  p_publication_mode public.publication_mode
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform public.assert_import_admin();
  perform public.validate_control_total_scales(p_control_total_fields, p_control_total_scales);
  insert into public.source_contract_versions (
    source_kind, version, required_sheet, required_headers, required_fields, control_total_fields,
    control_total_scales, publication_mode, created_by
  ) values (
    p_source_kind, p_version, p_required_sheet, p_required_headers, p_required_fields, p_control_total_fields,
    p_control_total_scales, p_publication_mode, auth.uid()
  ) on conflict (source_kind, version) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.source_contract_versions where source_kind = p_source_kind and version = p_version;
    if not exists (
      select 1 from public.source_contract_versions
      where id = v_id and required_sheet = p_required_sheet and required_headers = p_required_headers
        and required_fields = p_required_fields and control_total_fields = p_control_total_fields
        and control_total_scales = p_control_total_scales and publication_mode = p_publication_mode
    ) then
      raise exception 'Source contract versions are immutable; register a new version for changed content' using errcode = '23505';
    end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.register_source_contract(
  p_source_kind text, p_version text, p_required_sheet text, p_required_headers jsonb,
  p_required_fields jsonb, p_control_total_fields jsonb, p_publication_mode public.publication_mode
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_scales jsonb;
begin
  select coalesce(jsonb_object_agg(metric, 0), '{}'::jsonb) into v_scales
  from jsonb_object_keys(p_control_total_fields) as metric;
  return public.register_source_contract(
    p_source_kind, p_version, p_required_sheet, p_required_headers, p_required_fields,
    p_control_total_fields, v_scales, p_publication_mode
  );
end;
$$;

drop function if exists public.create_import_batch(uuid, text, text, jsonb, text, bigint, bigint, integer, jsonb);
create or replace function public.create_import_batch(
  p_source_contract_version_id uuid, p_scope_key text, p_source_sheet text, p_source_headers jsonb,
  p_file_hash text, p_file_size_bytes bigint, p_expected_rows bigint, p_expected_chunks integer,
  p_expected_control_totals jsonb
) returns public.import_batches language plpgsql security definer set search_path = public as $$
declare v_contract public.source_contract_versions; v_batch public.import_batches; v_batch_id uuid := gen_random_uuid();
begin
  perform public.assert_import_admin();
  select * into v_contract from public.source_contract_versions where id = p_source_contract_version_id and is_active;
  if not found then raise exception 'Unknown or retired source contract' using errcode = 'P0002'; end if;
  if p_source_sheet is distinct from v_contract.required_sheet or not (p_source_headers @> v_contract.required_headers) then
    raise exception 'Source recognition failed: sheet/header signature does not match contract' using errcode = '22023';
  end if;
  perform public.validate_control_total_scales(v_contract.control_total_fields, v_contract.control_total_scales);
  insert into public.import_batches (
    id, source_contract_version_id, source_kind, scope_key, source_sheet, source_headers, storage_object_path,
    declared_file_hash, file_size_bytes, expected_rows, expected_chunks, expected_control_totals, created_by
  ) values (
    v_batch_id, v_contract.id, v_contract.source_kind, p_scope_key, p_source_sheet, p_source_headers,
    'imports/' || v_batch_id::text || '/source.xlsx', lower(p_file_hash), p_file_size_bytes, p_expected_rows,
    p_expected_chunks, public.canonical_control_totals(p_expected_control_totals, v_contract.control_total_scales), auth.uid()
  ) on conflict (source_kind, scope_key, source_contract_version_id, declared_file_hash)
  do update set updated_at = now()
  returning * into v_batch;
  return v_batch;
end;
$$;

create or replace function public.reconcile_import_batch(p_batch_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_batch public.import_batches; v_contract public.source_contract_versions; v_run public.validation_runs;
declare v_actual jsonb; v_expected jsonb; v_id uuid; v_matched boolean;
begin
  perform public.assert_import_admin();
  select * into v_batch from public.import_batches where id = p_batch_id for update;
  if not found then raise exception 'Import batch was not found' using errcode = 'P0002'; end if;
  if v_batch.reconciliation_id is not null then return v_batch.reconciliation_id; end if;
  select * into v_run from public.validation_runs where id = v_batch.validation_run_id;
  if not found then raise exception 'Validation must run before reconciliation' using errcode = '55000'; end if;
  select * into v_contract from public.source_contract_versions where id = v_batch.source_contract_version_id;
  v_expected := public.canonical_control_totals(v_batch.expected_control_totals, v_contract.control_total_scales);
  select coalesce(jsonb_object_agg(spec.metric, to_jsonb(coalesce(t.total, 0))), '{}'::jsonb) into v_actual
  from jsonb_each_text(v_contract.control_total_fields) spec(metric, field_name)
  left join lateral (
    select sum((s.payload ->> spec.field_name)::numeric) as total
    from public.staging_rows s where s.batch_id = p_batch_id and s.row_status = 'VALID'
  ) t on true;
  v_actual := public.canonical_control_totals(v_actual, v_contract.control_total_scales);
  v_matched := v_batch.expected_rows = (v_run.valid_rows + v_run.excluded_rows + v_run.blocked_rows + v_run.duplicate_rows)
    and v_expected = v_actual and v_run.blocked_rows = 0;
  delete from public.import_reconciliations where batch_id = p_batch_id;
  insert into public.import_reconciliations (
    batch_id, parsed_rows, valid_rows, excluded_rows, blocked_rows, duplicate_rows,
    expected_control_totals, actual_control_totals, status
  ) values (
    p_batch_id, v_batch.expected_rows, v_run.valid_rows, v_run.excluded_rows, v_run.blocked_rows, v_run.duplicate_rows,
    v_expected, v_actual, case when v_matched then 'MATCHED' else 'MISMATCHED' end
  ) returning id into v_id;
  update public.import_batches set reconciliation_id = v_id,
    status = (case when v_matched then 'RECONCILED' else 'FAILED' end)::public.import_batch_status where id = p_batch_id;
  return v_id;
end;
$$;

grant execute on function public.register_source_contract(text, text, text, jsonb, jsonb, jsonb, jsonb, public.publication_mode) to authenticated;
grant execute on function public.canonical_control_totals(jsonb, jsonb) to authenticated;
grant execute on function public.create_import_batch(uuid, text, text, jsonb, text, bigint, bigint, integer, jsonb) to authenticated;
