-- Package 02: register the exact real CUSTOMER_MASTER export signature.

do $$
declare
  v_v2_count integer;
  v_v2 public.source_contract_versions;
  v_retired_at timestamptz := clock_timestamp();
begin
  select count(*) into v_v2_count
  from public.source_contract_versions
  where source_kind = 'CUSTOMER_MASTER' and version = '2';

  if v_v2_count <> 1 then
    raise exception 'CUSTOMER_MASTER version 2 guard failed: expected exactly one row, found %', v_v2_count;
  end if;

  select * into v_v2
  from public.source_contract_versions
  where source_kind = 'CUSTOMER_MASTER' and version = '2';

  if v_v2.created_by is not null
    or v_v2.is_active is distinct from true
    or v_v2.retired_at is not null
    or v_v2.required_sheet is distinct from 'Müşteri'
    or v_v2.required_headers is distinct from '["Müşteri","Müşteri Adı","Tabela Adı","Satış Temsilcisi Adı","Dist Satış Şefi Adı","Satış Kanalı Tanımı","Müşteri Hacim Segmenti","Müşteri Durumu"]'::jsonb
    or v_v2.required_fields is distinct from '["Müşteri","Müşteri Adı","Tabela Adı","Satış Temsilcisi Adı","Dist Satış Şefi Adı","Satış Kanalı Tanımı","Müşteri Hacim Segmenti","Müşteri Durumu"]'::jsonb
    or v_v2.control_total_fields is distinct from '{}'::jsonb
    or v_v2.control_total_scales is distinct from '{}'::jsonb
    or v_v2.publication_mode is distinct from 'FULL_REPLACE'::public.publication_mode then
    raise exception 'CUSTOMER_MASTER version 2 guard failed: definition or ownership differs from the known invalid contract';
  end if;

  if exists (
    select 1
    from public.import_batches
    where source_contract_version_id = v_v2.id
  ) then
    raise exception 'CUSTOMER_MASTER version 2 guard failed: import batches reference the contract';
  end if;

  update public.source_contract_versions
  set is_active = false, retired_at = v_retired_at
  where id = v_v2.id;

  perform public.register_system_source_contract(
    'CUSTOMER_MASTER', '3', 'SAPUI5 dışa aktarımı',
    '["Müşteri","Müşteri Adı","Tabela Adı","Satış Temsilcisi Adı","Dist Satış Şefi Adı","Satış Kanalı Tanımı","Müşteri Hacim Segmenti","Müşteri Durumu"]'::jsonb,
    '["Müşteri","Müşteri Adı","Tabela Adı","Satış Temsilcisi Adı","Dist Satış Şefi Adı","Satış Kanalı Tanımı","Müşteri Hacim Segmenti","Müşteri Durumu"]'::jsonb,
    '{}'::jsonb, '{}'::jsonb, 'FULL_REPLACE'::public.publication_mode
  );
end;
$$;
