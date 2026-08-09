-- Package 01: generic high-volume import, validation, reconciliation and publication backbone.
-- Domain packages add source contracts and adapters; they must not create another import pipeline.

create extension if not exists pgcrypto with schema extensions;

create type public.import_batch_status as enum (
  'CREATED', 'AWAITING_SOURCE_VERIFICATION', 'STAGING', 'VALIDATED', 'RECONCILED',
  'CANDIDATE_READY', 'PUBLISHING', 'PUBLISHED', 'FAILED'
);
create type public.staging_row_status as enum ('PENDING', 'VALID', 'EXCLUDED', 'BLOCKED', 'DUPLICATE');
create type public.candidate_status as enum ('READY', 'PUBLISHED', 'SUPERSEDED', 'FAILED');
create type public.publication_mode as enum ('FULL_REPLACE', 'APPEND_ONLY', 'UPSERT_VERSIONED');

create table public.source_contract_versions (
  id uuid primary key default gen_random_uuid(),
  source_kind text not null check (source_kind ~ '^[A-Z][A-Z0-9_]{1,63}$'),
  version text not null check (length(trim(version)) > 0),
  required_sheet text not null check (length(trim(required_sheet)) > 0),
  required_headers jsonb not null default '[]'::jsonb check (jsonb_typeof(required_headers) = 'array'),
  required_fields jsonb not null default '[]'::jsonb check (jsonb_typeof(required_fields) = 'array'),
  control_total_fields jsonb not null default '{}'::jsonb check (jsonb_typeof(control_total_fields) = 'object'),
  publication_mode public.publication_mode not null,
  is_active boolean not null default true,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  retired_at timestamptz,
  unique (source_kind, version)
);

create table public.import_batches (
  id uuid primary key default gen_random_uuid(),
  source_contract_version_id uuid not null references public.source_contract_versions(id),
  source_kind text not null,
  scope_key text not null check (length(trim(scope_key)) > 0),
  source_sheet text not null,
  source_headers jsonb not null check (jsonb_typeof(source_headers) = 'array'),
  storage_bucket text not null default 'source-evidence',
  storage_object_path text not null,
  declared_file_hash text not null check (declared_file_hash ~ '^[a-f0-9]{64}$'),
  verified_file_hash text check (verified_file_hash is null or verified_file_hash ~ '^[a-f0-9]{64}$'),
  file_size_bytes bigint not null check (file_size_bytes >= 0),
  expected_rows bigint not null check (expected_rows >= 0),
  expected_chunks integer not null check (expected_chunks >= 0),
  received_chunks integer not null default 0 check (received_chunks >= 0),
  staged_rows bigint not null default 0 check (staged_rows >= 0),
  expected_control_totals jsonb not null default '{}'::jsonb check (jsonb_typeof(expected_control_totals) = 'object'),
  status public.import_batch_status not null default 'AWAITING_SOURCE_VERIFICATION',
  source_verified_at timestamptz,
  validation_run_id uuid,
  reconciliation_id uuid,
  published_publication_id uuid,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  completed_at timestamptz,
  unique (source_kind, scope_key, source_contract_version_id, declared_file_hash)
);

create table public.import_chunks (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null references public.import_batches(id) on delete cascade,
  chunk_no integer not null check (chunk_no >= 0),
  row_offset bigint not null check (row_offset >= 0),
  chunk_hash text not null check (chunk_hash ~ '^[a-f0-9]{64}$'),
  server_chunk_hash text not null check (server_chunk_hash ~ '^[a-f0-9]{64}$'),
  row_count integer not null check (row_count >= 0),
  created_at timestamptz not null default now(),
  unique (batch_id, chunk_no),
  unique (batch_id, chunk_no, chunk_hash, row_count)
);

create table public.staging_rows (
  id bigint generated always as identity primary key,
  batch_id uuid not null references public.import_batches(id) on delete cascade,
  chunk_id uuid not null references public.import_chunks(id) on delete cascade,
  source_row_no bigint not null check (source_row_no > 0),
  payload jsonb not null check (jsonb_typeof(payload) = 'object'),
  payload_hash text not null check (payload_hash ~ '^[a-f0-9]{64}$'),
  row_status public.staging_row_status not null default 'PENDING',
  created_at timestamptz not null default now(),
  unique (batch_id, source_row_no)
);

create table public.validation_runs (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null unique references public.import_batches(id) on delete cascade,
  contract_version_id uuid not null references public.source_contract_versions(id),
  valid_rows bigint not null default 0,
  excluded_rows bigint not null default 0,
  blocked_rows bigint not null default 0,
  duplicate_rows bigint not null default 0,
  status text not null check (status in ('PASSED', 'BLOCKED')),
  created_at timestamptz not null default now()
);

create table public.validation_issues (
  id bigint generated always as identity primary key,
  validation_run_id uuid not null references public.validation_runs(id) on delete cascade,
  staging_row_id bigint references public.staging_rows(id) on delete cascade,
  severity text not null check (severity in ('BLOCKING', 'EXCLUDED', 'DUPLICATE')),
  code text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table public.import_reconciliations (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null unique references public.import_batches(id) on delete cascade,
  parsed_rows bigint not null,
  valid_rows bigint not null,
  excluded_rows bigint not null,
  blocked_rows bigint not null,
  duplicate_rows bigint not null,
  expected_control_totals jsonb not null,
  actual_control_totals jsonb not null,
  status text not null check (status in ('MATCHED', 'MISMATCHED')),
  created_at timestamptz not null default now()
);

create table public.candidate_publications (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid not null unique references public.import_batches(id) on delete cascade,
  validation_run_id uuid not null references public.validation_runs(id),
  reconciliation_id uuid not null references public.import_reconciliations(id),
  manifest jsonb not null,
  status public.candidate_status not null default 'READY',
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  published_at timestamptz
);

create table public.publications (
  id uuid primary key default gen_random_uuid(),
  candidate_id uuid not null unique references public.candidate_publications(id),
  source_kind text not null,
  scope_key text not null,
  version integer not null check (version > 0),
  manifest jsonb not null,
  published_by uuid not null references auth.users(id),
  published_at timestamptz not null default now(),
  superseded_at timestamptz,
  unique (source_kind, scope_key, version)
);

create table public.publication_heads (
  source_kind text not null,
  scope_key text not null,
  active_publication_id uuid not null references public.publications(id),
  version integer not null check (version > 0),
  updated_at timestamptz not null default now(),
  primary key (source_kind, scope_key)
);

alter table public.import_batches
  add constraint import_batches_validation_run_fk foreign key (validation_run_id) references public.validation_runs(id),
  add constraint import_batches_reconciliation_fk foreign key (reconciliation_id) references public.import_reconciliations(id),
  add constraint import_batches_publication_fk foreign key (published_publication_id) references public.publications(id);

create index import_batches_status_created_idx on public.import_batches(status, created_at desc);
create index import_chunks_batch_idx on public.import_chunks(batch_id, chunk_no);
create index staging_rows_batch_status_idx on public.staging_rows(batch_id, row_status, source_row_no);
create index validation_issues_run_idx on public.validation_issues(validation_run_id, severity, staging_row_id);

create trigger import_batches_set_updated_at before update on public.import_batches
for each row execute function public.set_updated_at();

create or replace function public.assert_import_admin()
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    raise exception 'Package 01 mutation requires an authenticated admin' using errcode = '42501';
  end if;
end;
$$;

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

create or replace function public.create_import_batch(
  p_source_contract_version_id uuid, p_scope_key text, p_source_sheet text, p_source_headers jsonb,
  p_file_hash text, p_file_size_bytes bigint, p_expected_rows bigint,
  p_expected_chunks integer, p_expected_control_totals jsonb
) returns public.import_batches language plpgsql security definer set search_path = public as $$
declare v_contract public.source_contract_versions; v_batch public.import_batches; v_batch_id uuid := gen_random_uuid();
begin
  perform public.assert_import_admin();
  select * into v_contract from public.source_contract_versions where id = p_source_contract_version_id and is_active;
  if not found then raise exception 'Unknown or retired source contract' using errcode = 'P0002'; end if;
  if p_source_sheet is distinct from v_contract.required_sheet
    or not (p_source_headers @> v_contract.required_headers) then
    raise exception 'Source recognition failed: sheet/header signature does not match contract' using errcode = '22023';
  end if;
  insert into public.import_batches (
    id, source_contract_version_id, source_kind, scope_key, source_sheet, source_headers, storage_object_path,
    declared_file_hash, file_size_bytes, expected_rows, expected_chunks, expected_control_totals, created_by
  ) values (
    v_batch_id, v_contract.id, v_contract.source_kind, p_scope_key, p_source_sheet, p_source_headers, 'imports/' || v_batch_id::text || '/source.xlsx',
    lower(p_file_hash), p_file_size_bytes, p_expected_rows, p_expected_chunks, p_expected_control_totals, auth.uid()
  ) on conflict (source_kind, scope_key, source_contract_version_id, declared_file_hash)
  do update set updated_at = now()
  returning * into v_batch;
  return v_batch;
end;
$$;

-- Called only by a backend orchestration boundary after it has SHA-256 hashed the private Storage object.
create or replace function public.verify_import_source_hash(
  p_batch_id uuid, p_verified_file_hash text, p_verified_file_size_bytes bigint
) returns void language plpgsql security definer set search_path = public as $$
declare v_batch public.import_batches;
begin
  if auth.role() is distinct from 'service_role' then
    raise exception 'Source verification is restricted to the trusted backend' using errcode = '42501';
  end if;
  select * into v_batch from public.import_batches where id = p_batch_id for update;
  if not found then raise exception 'Import batch was not found' using errcode = 'P0002'; end if;
  if v_batch.declared_file_hash <> lower(p_verified_file_hash) or v_batch.file_size_bytes <> p_verified_file_size_bytes then
    update public.import_batches set status = 'FAILED' where id = p_batch_id;
    raise exception 'Server source hash or byte-size verification failed' using errcode = '22000';
  end if;
  update public.import_batches set verified_file_hash = lower(p_verified_file_hash), source_verified_at = now(), status = 'CREATED'
  where id = p_batch_id;
end;
$$;

create or replace function public.stage_import_chunk(
  p_batch_id uuid, p_chunk_no integer, p_row_offset bigint, p_chunk_hash text, p_row_count integer, p_rows jsonb
) returns uuid language plpgsql security definer set search_path = public, extensions as $$
declare v_batch public.import_batches; v_existing public.import_chunks; v_chunk_id uuid;
declare v_server_hash text := encode(extensions.digest(convert_to(p_rows::text, 'UTF8'), 'sha256'), 'hex');
begin
  perform public.assert_import_admin();
  if jsonb_typeof(p_rows) <> 'array' or jsonb_array_length(p_rows) <> p_row_count then
    raise exception 'Chunk row_count does not match its JSON array' using errcode = '22023';
  end if;
  select * into v_batch from public.import_batches where id = p_batch_id for update;
  if not found then raise exception 'Import batch was not found' using errcode = 'P0002'; end if;
  if v_batch.source_verified_at is null or v_batch.status not in ('CREATED', 'STAGING') then
    raise exception 'Batch is not eligible for staging' using errcode = '55000';
  end if;
  select * into v_existing from public.import_chunks where batch_id = p_batch_id and chunk_no = p_chunk_no;
  if found then
    if v_existing.chunk_hash = lower(p_chunk_hash) and v_existing.row_count = p_row_count
      and v_existing.row_offset = p_row_offset and v_existing.server_chunk_hash = v_server_hash then
      return v_existing.id;
    end if;
    raise exception 'Chunk retry conflicts with content, offset, or row count' using errcode = '23505';
  end if;
  insert into public.import_chunks (batch_id, chunk_no, row_offset, chunk_hash, server_chunk_hash, row_count)
  values (p_batch_id, p_chunk_no, p_row_offset, lower(p_chunk_hash), v_server_hash, p_row_count) returning id into v_chunk_id;
  insert into public.staging_rows (batch_id, chunk_id, source_row_no, payload, payload_hash)
  select p_batch_id, v_chunk_id, p_row_offset + item.ordinality,
    item.value, encode(extensions.digest(convert_to(item.value::text, 'UTF8'), 'sha256'), 'hex')
  from jsonb_array_elements(p_rows) with ordinality as item(value, ordinality);
  update public.import_batches
  set received_chunks = received_chunks + 1, staged_rows = staged_rows + p_row_count, status = 'STAGING'
  where id = p_batch_id;
  return v_chunk_id;
end;
$$;

create or replace function public.validate_import_batch(p_batch_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_batch public.import_batches; v_contract public.source_contract_versions; v_run_id uuid;
begin
  perform public.assert_import_admin();
  select * into v_batch from public.import_batches where id = p_batch_id for update;
  if not found or v_batch.source_verified_at is null then raise exception 'Verified import batch is required' using errcode = '55000'; end if;
  if v_batch.validation_run_id is not null then return v_batch.validation_run_id; end if;
  if v_batch.received_chunks <> v_batch.expected_chunks or v_batch.staged_rows <> v_batch.expected_rows then
    raise exception 'All expected chunks and rows must be staged before validation' using errcode = '55000';
  end if;
  select * into v_contract from public.source_contract_versions where id = v_batch.source_contract_version_id;
  update public.staging_rows set row_status = 'PENDING' where batch_id = p_batch_id;
  update public.staging_rows s set row_status = 'EXCLUDED'
  where s.batch_id = p_batch_id and coalesce(s.payload ->> '__exclude_reason', '') <> '';
  update public.staging_rows s set row_status = 'DUPLICATE'
  where s.batch_id = p_batch_id and s.row_status = 'PENDING'
    and exists (select 1 from public.staging_rows earlier where earlier.batch_id = s.batch_id
      and earlier.payload_hash = s.payload_hash and earlier.source_row_no < s.source_row_no);
  update public.staging_rows s set row_status = 'BLOCKED'
  where s.batch_id = p_batch_id and s.row_status = 'PENDING'
    and exists (select 1 from jsonb_array_elements_text(v_contract.required_fields) field(name)
      where nullif(btrim(s.payload ->> field.name), '') is null);
  update public.staging_rows s set row_status = 'BLOCKED'
  where s.batch_id = p_batch_id and s.row_status = 'PENDING'
    and exists (select 1 from jsonb_each_text(v_contract.control_total_fields) spec(metric, field_name)
      where coalesce(s.payload ->> spec.field_name, '') !~ '^-?(0|[1-9][0-9]*)(\.[0-9]+)?$');
  update public.staging_rows set row_status = 'VALID' where batch_id = p_batch_id and row_status = 'PENDING';
  insert into public.validation_runs (batch_id, contract_version_id, valid_rows, excluded_rows, blocked_rows, duplicate_rows, status)
  select p_batch_id, v_contract.id,
    count(*) filter (where row_status = 'VALID'), count(*) filter (where row_status = 'EXCLUDED'),
    count(*) filter (where row_status = 'BLOCKED'), count(*) filter (where row_status = 'DUPLICATE'),
    case when count(*) filter (where row_status = 'BLOCKED') = 0 then 'PASSED' else 'BLOCKED' end
  from public.staging_rows where batch_id = p_batch_id returning id into v_run_id;
  insert into public.validation_issues (validation_run_id, staging_row_id, severity, code, detail)
  select v_run_id, s.id,
    case s.row_status when 'BLOCKED' then 'BLOCKING' when 'DUPLICATE' then 'DUPLICATE' else 'EXCLUDED' end,
    case s.row_status when 'BLOCKED' then 'MISSING_REQUIRED_FIELD' when 'DUPLICATE' then 'DUPLICATE_PAYLOAD' else 'EXCLUDED_BY_SOURCE' end,
    jsonb_build_object('source_row_no', s.source_row_no)
  from public.staging_rows s where s.batch_id = p_batch_id and s.row_status <> 'VALID';
  update public.import_batches set validation_run_id = v_run_id, status = 'VALIDATED' where id = p_batch_id;
  return v_run_id;
end;
$$;

create or replace function public.reconcile_import_batch(p_batch_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_batch public.import_batches; v_contract public.source_contract_versions; v_run public.validation_runs;
declare v_actual jsonb; v_id uuid; v_matched boolean;
begin
  perform public.assert_import_admin();
  select * into v_batch from public.import_batches where id = p_batch_id for update;
  select * into v_run from public.validation_runs where id = v_batch.validation_run_id;
  if not found then raise exception 'Validation must run before reconciliation' using errcode = '55000'; end if;
  select * into v_contract from public.source_contract_versions where id = v_batch.source_contract_version_id;
  select coalesce(jsonb_object_agg(spec.metric, to_jsonb(coalesce(t.total, 0))), '{}'::jsonb) into v_actual
  from jsonb_each_text(v_contract.control_total_fields) spec(metric, field_name)
  left join lateral (
    select sum((s.payload ->> spec.field_name)::numeric) as total
    from public.staging_rows s where s.batch_id = p_batch_id and s.row_status = 'VALID'
  ) t on true;
  v_matched := v_batch.expected_rows = (v_run.valid_rows + v_run.excluded_rows + v_run.blocked_rows + v_run.duplicate_rows)
    and v_batch.expected_control_totals = v_actual and v_run.blocked_rows = 0;
  delete from public.import_reconciliations where batch_id = p_batch_id;
  insert into public.import_reconciliations (
    batch_id, parsed_rows, valid_rows, excluded_rows, blocked_rows, duplicate_rows,
    expected_control_totals, actual_control_totals, status
  ) values (
    p_batch_id, v_batch.expected_rows, v_run.valid_rows, v_run.excluded_rows, v_run.blocked_rows, v_run.duplicate_rows,
    v_batch.expected_control_totals, v_actual, case when v_matched then 'MATCHED' else 'MISMATCHED' end
  ) returning id into v_id;
  update public.import_batches set reconciliation_id = v_id,
    status = (case when v_matched then 'RECONCILED' else 'FAILED' end)::public.import_batch_status
  where id = p_batch_id;
  return v_id;
end;
$$;

create or replace function public.create_candidate_publication(p_batch_id uuid, p_manifest jsonb)
returns uuid language plpgsql security definer set search_path = public as $$
declare v_batch public.import_batches; v_id uuid;
begin
  perform public.assert_import_admin();
  select * into v_batch from public.import_batches where id = p_batch_id for update;
  if v_batch.status <> 'RECONCILED' then raise exception 'Only exactly reconciled batches can become candidates' using errcode = '55000'; end if;
  insert into public.candidate_publications (batch_id, validation_run_id, reconciliation_id, manifest, created_by)
  values (p_batch_id, v_batch.validation_run_id, v_batch.reconciliation_id, p_manifest, auth.uid())
  on conflict (batch_id) do update set manifest = excluded.manifest
  returning id into v_id;
  update public.import_batches set status = 'CANDIDATE_READY' where id = p_batch_id;
  return v_id;
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
  return v_publication_id;
end;
$$;

insert into storage.buckets (id, name, public) values ('source-evidence', 'source-evidence', false) on conflict (id) do update set public = false;

alter table public.source_contract_versions enable row level security;
alter table public.import_batches enable row level security;
alter table public.import_chunks enable row level security;
alter table public.staging_rows enable row level security;
alter table public.validation_runs enable row level security;
alter table public.validation_issues enable row level security;
alter table public.import_reconciliations enable row level security;
alter table public.candidate_publications enable row level security;
alter table public.publications enable row level security;
alter table public.publication_heads enable row level security;

create policy import_admin_read on public.import_batches for select to authenticated using (public.is_admin());
create policy import_admin_read on public.source_contract_versions for select to authenticated using (public.is_admin());
create policy import_admin_read on public.import_chunks for select to authenticated using (public.is_admin());
create policy import_admin_read on public.staging_rows for select to authenticated using (public.is_admin());
create policy import_admin_read on public.validation_runs for select to authenticated using (public.is_admin());
create policy import_admin_read on public.validation_issues for select to authenticated using (public.is_admin());
create policy import_admin_read on public.import_reconciliations for select to authenticated using (public.is_admin());
create policy import_admin_read on public.candidate_publications for select to authenticated using (public.is_admin());
create policy authenticated_read_publications on public.publications for select to authenticated using (true);
create policy authenticated_read_publication_heads on public.publication_heads for select to authenticated using (true);
create policy import_admin_storage on storage.objects for all to authenticated using (bucket_id = 'source-evidence' and public.is_admin()) with check (bucket_id = 'source-evidence' and public.is_admin());

revoke all on table public.source_contract_versions, public.import_batches, public.import_chunks, public.staging_rows,
  public.validation_runs, public.validation_issues, public.import_reconciliations, public.candidate_publications,
  public.publications, public.publication_heads from anon, authenticated;
grant select on public.publications, public.publication_heads to authenticated;
grant select on public.source_contract_versions, public.import_batches, public.import_chunks, public.staging_rows,
  public.validation_runs, public.validation_issues, public.import_reconciliations, public.candidate_publications
to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant execute on function public.register_source_contract(text, text, text, jsonb, jsonb, jsonb, public.publication_mode) to authenticated;
grant execute on function public.create_import_batch(uuid, text, text, jsonb, text, bigint, bigint, integer, jsonb) to authenticated;
grant execute on function public.stage_import_chunk(uuid, integer, bigint, text, integer, jsonb) to authenticated;
grant execute on function public.validate_import_batch(uuid) to authenticated;
grant execute on function public.reconcile_import_batch(uuid) to authenticated;
grant execute on function public.create_candidate_publication(uuid, jsonb) to authenticated;
grant execute on function public.publish_candidate(uuid, uuid) to authenticated;
grant execute on function public.verify_import_source_hash(uuid, text, bigint) to service_role;

comment on table public.import_batches is 'Package 01 import attempt. The unique file/contract/scope identity makes retries idempotent.';
comment on table public.staging_rows is 'Temporary set-based import payload; retention is controlled by a later cleanup policy.';
comment on function public.publish_candidate(uuid, uuid) is 'Atomically advances one source+scope publication pointer after a current validated reconciliation.';
