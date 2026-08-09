-- Package 01 narrow-audit remediation: immutable contract provenance, idempotent reconciliation,
-- verified chunk integrity and batch-identity-bound private Storage paths.

create or replace function public.canonical_import_json(p_value jsonb)
returns text language plpgsql immutable strict set search_path = public as $$
declare v_type text;
begin
  v_type := jsonb_typeof(p_value);
  if v_type = 'array' then
    return '[' || coalesce((select string_agg(public.canonical_import_json(value), ',' order by ordinality)
      from jsonb_array_elements(p_value) with ordinality as item(value, ordinality)), '') || ']';
  end if;
  if v_type = 'object' then
    return '{' || coalesce((select string_agg(to_jsonb(key)::text || ':' || public.canonical_import_json(p_value -> key), ',' order by key collate "C")
      from jsonb_object_keys(p_value) as key), '') || '}';
  end if;
  return p_value::text;
end;
$$;

create or replace function public.import_chunk_payload_hash(p_rows jsonb)
returns text language sql immutable strict set search_path = public, extensions as $$
  select encode(extensions.digest(convert_to(public.canonical_import_json(p_rows), 'UTF8'), 'sha256'), 'hex');
$$;

create or replace function public.prevent_used_source_contract_mutation()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if exists (select 1 from public.import_batches where source_contract_version_id = old.id)
    and (new.source_kind, new.version, new.required_sheet, new.required_headers, new.required_fields,
         new.control_total_fields, new.publication_mode)
      is distinct from
        (old.source_kind, old.version, old.required_sheet, old.required_headers, old.required_fields,
         old.control_total_fields, old.publication_mode) then
    raise exception 'A source contract definition cannot change after an import batch uses it' using errcode = '55000';
  end if;
  return new;
end;
$$;

drop trigger if exists source_contract_versions_prevent_used_mutation on public.source_contract_versions;
create trigger source_contract_versions_prevent_used_mutation
before update on public.source_contract_versions
for each row execute function public.prevent_used_source_contract_mutation();

create or replace function public.register_source_contract(
  p_source_kind text, p_version text, p_required_sheet text, p_required_headers jsonb,
  p_required_fields jsonb, p_control_total_fields jsonb, p_publication_mode public.publication_mode
) returns uuid language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  perform public.assert_import_admin();
  insert into public.source_contract_versions (
    source_kind, version, required_sheet, required_headers, required_fields, control_total_fields, publication_mode, created_by
  ) values (p_source_kind, p_version, p_required_sheet, p_required_headers, p_required_fields, p_control_total_fields, p_publication_mode, auth.uid())
  on conflict (source_kind, version) do nothing
  returning id into v_id;
  if v_id is null then
    select id into v_id from public.source_contract_versions where source_kind = p_source_kind and version = p_version;
    if not exists (
      select 1 from public.source_contract_versions
      where id = v_id and required_sheet = p_required_sheet and required_headers = p_required_headers
        and required_fields = p_required_fields and control_total_fields = p_control_total_fields
        and publication_mode = p_publication_mode
    ) then
      raise exception 'Source contract versions are immutable; register a new version for changed content' using errcode = '23505';
    end if;
  end if;
  return v_id;
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
  insert into public.import_batches (
    id, source_contract_version_id, source_kind, scope_key, source_sheet, source_headers, storage_object_path,
    declared_file_hash, file_size_bytes, expected_rows, expected_chunks, expected_control_totals, created_by
  ) values (
    v_batch_id, v_contract.id, v_contract.source_kind, p_scope_key, p_source_sheet, p_source_headers,
    'imports/' || v_batch_id::text || '/source.xlsx', lower(p_file_hash), p_file_size_bytes, p_expected_rows,
    p_expected_chunks, p_expected_control_totals, auth.uid()
  ) on conflict (source_kind, scope_key, source_contract_version_id, declared_file_hash)
  do update set updated_at = now()
  returning * into v_batch;
  return v_batch;
end;
$$;

alter table public.import_batches add constraint import_batches_server_generated_storage_path
  check (storage_object_path = 'imports/' || id::text || '/source.xlsx') not valid;

create or replace function public.stage_import_chunk(
  p_batch_id uuid, p_chunk_no integer, p_row_offset bigint, p_chunk_hash text, p_row_count integer, p_rows jsonb
) returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_batch public.import_batches; v_existing public.import_chunks; v_chunk_id uuid;
declare v_server_hash text := public.import_chunk_payload_hash(p_rows);
begin
  perform public.assert_import_admin();
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) <> p_row_count then
    raise exception 'Chunk row_count does not match its JSON array' using errcode = '22023';
  end if;
  if lower(p_chunk_hash) <> v_server_hash then
    raise exception 'Client chunk hash does not match the server-calculated payload digest' using errcode = '22000';
  end if;
  select * into v_batch from public.import_batches where id = p_batch_id for update;
  if not found then raise exception 'Import batch was not found' using errcode = 'P0002'; end if;
  if v_batch.source_verified_at is null or v_batch.status not in ('CREATED', 'STAGING') then
    raise exception 'Batch is not eligible for staging' using errcode = '55000';
  end if;
  select * into v_existing from public.import_chunks where batch_id = p_batch_id and chunk_no = p_chunk_no;
  if found then
    if v_existing.chunk_hash = lower(p_chunk_hash) and v_existing.row_count = p_row_count
      and v_existing.row_offset = p_row_offset and v_existing.server_chunk_hash = v_server_hash then return v_existing.id; end if;
    raise exception 'Chunk retry conflicts with content, offset, or row count' using errcode = '23505';
  end if;
  insert into public.import_chunks (batch_id, chunk_no, row_offset, chunk_hash, server_chunk_hash, row_count)
  values (p_batch_id, p_chunk_no, p_row_offset, lower(p_chunk_hash), v_server_hash, p_row_count) returning id into v_chunk_id;
  insert into public.staging_rows (batch_id, chunk_id, source_row_no, payload, payload_hash)
  select p_batch_id, v_chunk_id, p_row_offset + item.ordinality, item.value,
    encode(extensions.digest(convert_to(item.value::text, 'UTF8'), 'sha256'), 'hex')
  from jsonb_array_elements(p_rows) with ordinality as item(value, ordinality);
  update public.import_batches set received_chunks = received_chunks + 1, staged_rows = staged_rows + p_row_count, status = 'STAGING' where id = p_batch_id;
  return v_chunk_id;
end;
$$;

create or replace function public.reconcile_import_batch(p_batch_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_batch public.import_batches; v_contract public.source_contract_versions; v_run public.validation_runs;
declare v_actual jsonb; v_id uuid; v_matched boolean;
begin
  perform public.assert_import_admin();
  select * into v_batch from public.import_batches where id = p_batch_id for update;
  if not found then raise exception 'Import batch was not found' using errcode = 'P0002'; end if;
  if v_batch.reconciliation_id is not null then return v_batch.reconciliation_id; end if;
  select * into v_run from public.validation_runs where id = v_batch.validation_run_id;
  if not found then raise exception 'Validation must run before reconciliation' using errcode = '55000'; end if;
  select * into v_contract from public.source_contract_versions where id = v_batch.source_contract_version_id;
  select coalesce(jsonb_object_agg(spec.metric, to_jsonb(coalesce(t.total, 0))), '{}'::jsonb) into v_actual
  from jsonb_each_text(v_contract.control_total_fields) spec(metric, field_name)
  left join lateral (select sum((s.payload ->> spec.field_name)::numeric) as total from public.staging_rows s
    where s.batch_id = p_batch_id and s.row_status = 'VALID') t on true;
  v_matched := v_batch.expected_rows = (v_run.valid_rows + v_run.excluded_rows + v_run.blocked_rows + v_run.duplicate_rows)
    and v_batch.expected_control_totals = v_actual and v_run.blocked_rows = 0;
  insert into public.import_reconciliations (batch_id, parsed_rows, valid_rows, excluded_rows, blocked_rows, duplicate_rows,
    expected_control_totals, actual_control_totals, status)
  values (p_batch_id, v_batch.expected_rows, v_run.valid_rows, v_run.excluded_rows, v_run.blocked_rows, v_run.duplicate_rows,
    v_batch.expected_control_totals, v_actual, case when v_matched then 'MATCHED' else 'MISMATCHED' end) returning id into v_id;
  update public.import_batches set reconciliation_id = v_id,
    status = (case when v_matched then 'RECONCILED' else 'FAILED' end)::public.import_batch_status where id = p_batch_id;
  return v_id;
end;
$$;

drop policy if exists import_admin_storage on storage.objects;
create policy source_evidence_admin_read on storage.objects for select to authenticated
  using (bucket_id = 'source-evidence' and public.is_admin());
create policy source_evidence_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'source-evidence' and public.is_admin() and exists (
    select 1 from public.import_batches b where b.storage_bucket = bucket_id and b.storage_object_path = name
      and b.created_by = auth.uid() and b.source_verified_at is null));
create policy source_evidence_admin_update on storage.objects for update to authenticated
  using (bucket_id = 'source-evidence' and public.is_admin() and exists (
    select 1 from public.import_batches b where b.storage_bucket = bucket_id and b.storage_object_path = name
      and b.created_by = auth.uid() and b.source_verified_at is null))
  with check (bucket_id = 'source-evidence' and public.is_admin());
create policy source_evidence_admin_delete on storage.objects for delete to authenticated
  using (bucket_id = 'source-evidence' and public.is_admin() and exists (
    select 1 from public.import_batches b where b.storage_bucket = bucket_id and b.storage_object_path = name
      and b.created_by = auth.uid() and b.source_verified_at is null));

revoke all on function public.create_import_batch(uuid, text, text, jsonb, text, bigint, bigint, integer, jsonb) from public;
grant execute on function public.create_import_batch(uuid, text, text, jsonb, text, bigint, bigint, integer, jsonb) to authenticated;
revoke all on function public.import_chunk_payload_hash(jsonb) from public;
grant execute on function public.import_chunk_payload_hash(jsonb) to authenticated;
