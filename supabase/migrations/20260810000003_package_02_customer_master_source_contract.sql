-- Package 02: migration-owned canonical CUSTOMER_MASTER source contract.

alter table public.source_contract_versions
  alter column created_by drop not null;

create or replace function public.register_system_source_contract(
  p_source_kind text, p_version text, p_required_sheet text, p_required_headers jsonb,
  p_required_fields jsonb, p_control_total_fields jsonb, p_control_total_scales jsonb,
  p_publication_mode public.publication_mode
) returns uuid language plpgsql set search_path = public as $$
declare v_id uuid; v_existing public.source_contract_versions;
begin
  perform public.validate_control_total_scales(p_control_total_fields, p_control_total_scales);
  insert into public.source_contract_versions (
    source_kind, version, required_sheet, required_headers, required_fields, control_total_fields,
    control_total_scales, publication_mode, created_by, is_active, retired_at
  ) values (
    p_source_kind, p_version, p_required_sheet, p_required_headers, p_required_fields, p_control_total_fields,
    p_control_total_scales, p_publication_mode, null, true, null
  ) on conflict (source_kind, version) do nothing
  returning id into v_id;
  if v_id is null then
    select * into v_existing
    from public.source_contract_versions
    where source_kind = p_source_kind and version = p_version;
    if v_existing.required_sheet is distinct from p_required_sheet
      or v_existing.required_headers is distinct from p_required_headers
      or v_existing.required_fields is distinct from p_required_fields
      or v_existing.control_total_fields is distinct from p_control_total_fields
      or v_existing.control_total_scales is distinct from p_control_total_scales
      or v_existing.publication_mode is distinct from p_publication_mode then
      raise exception 'Source contract versions are immutable; register a new version for changed content' using errcode = '23505';
    end if;
    if v_existing.is_active is distinct from true or v_existing.retired_at is not null then
      raise exception 'Existing system source contract is not active and cannot be reused as the canonical contract' using errcode = '55000';
    end if;
    v_id := v_existing.id;
  end if;
  return v_id;
end;
$$;

comment on function public.register_system_source_contract(text, text, text, jsonb, jsonb, jsonb, jsonb, public.publication_mode) is
  'Migration-owned canonical source contract registration; writes created_by = NULL and is not a runtime API.';

revoke all on function public.register_system_source_contract(text, text, text, jsonb, jsonb, jsonb, jsonb, public.publication_mode) from public, anon, authenticated, service_role;

do $$
begin
  perform public.register_system_source_contract(
    'CUSTOMER_MASTER', '2', 'Müşteri',
    '["Müşteri","Müşteri Adı","Tabela Adı","Satış Temsilcisi Adı","Dist Satış Şefi Adı","Satış Kanalı Tanımı","Müşteri Hacim Segmenti","Müşteri Durumu"]'::jsonb,
    '["Müşteri","Müşteri Adı","Tabela Adı","Satış Temsilcisi Adı","Dist Satış Şefi Adı","Satış Kanalı Tanımı","Müşteri Hacim Segmenti","Müşteri Durumu"]'::jsonb,
    '{}'::jsonb, '{}'::jsonb, 'FULL_REPLACE'::public.publication_mode
  );
end;
$$;
