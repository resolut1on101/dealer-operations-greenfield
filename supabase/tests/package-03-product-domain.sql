begin;

create or replace function pg_temp.assert_true(p_condition boolean, p_message text)
returns void language plpgsql as $$
begin
  if coalesce(p_condition,false) is not true then
    raise exception 'ASSERTION FAILED: %', p_message;
  end if;
end;
$$;

do $$
declare
  v_ref uuid;
  v_exact numeric;
  v_display numeric;
  v_fkns bigint;
  v_canonical_rows bigint;
begin
  select id into v_ref
  from public.product_conversion_reference_versions
  where scope_key='1237' and version='paket-51fb373c-v1' and is_active;

  perform pg_temp.assert_true(v_ref is not null, 'active paket reference must exist');
  perform pg_temp.assert_true(
    (select evidence_sha256='51fb373ca178b68a8ddd29a6ea8f65f54162137c78aaccfb9b7f93805ffffdf2'
     and evidence_row_count=331 and product_code_count=84 and directed_relation_count=59 and component_count=36
     from public.product_conversion_reference_versions where id=v_ref),
    'reference metadata must match exact paket.xlsx evidence'
  );

  perform pg_temp.assert_true(
    (select count(*)=59 and sum(observation_count)=331
     from public.product_conversion_reference_edges where reference_version_id=v_ref),
    '59 stable relations must conserve all 331 observations'
  );
  perform pg_temp.assert_true(
    (select count(*)=84 and count(distinct canonical_product_code)=36
     from public.product_canonical_mappings where reference_version_id=v_ref),
    '84 raw codes must normalize to exactly 36 canonical products'
  );

  -- paket.xlsx is not a runtime/user-upload contract anymore.
  perform pg_temp.assert_true(
    not exists(select 1 from public.source_contract_versions where source_kind='PRODUCT_CONVERSION' and is_active),
    'PRODUCT_CONVERSION upload contract must be retired'
  );

  -- Standard direction: 12 L main product 150021; 6 L / 3 L split codes collapse into it.
  perform pg_temp.assert_true(public.canonical_product_code('1237','150021')='150021', '150021 remains canonical');
  perform pg_temp.assert_true(public.canonical_product_code('1237','154525')='150021', '154525 split code normalizes to 150021');
  perform pg_temp.assert_true(public.canonical_product_code('1237','154548')='150021', '154548 split code normalizes to 150021');
  perform pg_temp.assert_true(public.canonical_product_quantity('1237','154525',1)=0.5, '154525 exact factor is 1/2 of 150021');
  perform pg_temp.assert_true(public.canonical_product_quantity('1237','154548',1)=0.25, '154548 exact factor is 1/4 of 150021');

  -- Exact backend math stays fractional. Only presentation rounds the copy.
  with stock(raw_code, raw_quantity) as (
    values ('150021'::text,10::numeric), ('154525',1), ('154548',1)
  )
  select sum(public.canonical_product_quantity('1237',raw_code,raw_quantity))
  into v_exact
  from stock;
  v_display := round(v_exact);
  perform pg_temp.assert_true(v_exact=10.75, 'backend canonical quantity must remain exact 10.75');
  perform pg_temp.assert_true(v_display=11, 'UX display may round exact 10.75 to 11');
  perform pg_temp.assert_true(v_exact*12=129, 'litre math must use 10.75, not rounded 11');

  -- FKNS semantics: selling any split code fulfills the same canonical product at the point;
  -- the same customer is counted once even if main and split codes were both sold.
  with sales(customer_id, raw_code, raw_quantity) as (
    values
      ('5000000001'::text,'154548'::text,1::numeric),
      ('5000000001','150021',1),
      ('5000000002','154525',1),
      ('5000000003','999999',1)
  ), normalized as (
    select customer_id, public.canonical_product_code('1237',raw_code) as canonical_code
    from sales where raw_quantity > 0
  )
  select count(distinct customer_id) into v_fkns
  from normalized where canonical_code='150021';
  perform pg_temp.assert_true(v_fkns=2, 'FKNS must count split/main sales as the same product and unique customer once');

  -- High alcohol runs in the opposite direction: case/multipack -> single retail code.
  perform pg_temp.assert_true(public.canonical_product_code('1237','152224')='152315', 'high-alcohol case code 152224 normalizes to single code 152315');
  perform pg_temp.assert_true(public.canonical_product_quantity('1237','152224',1)=24, 'one 152224 case equals exactly 24 canonical 152315 units');
  perform pg_temp.assert_true(public.canonical_product_code('1237','152315')='152315', 'single high-alcohol code remains canonical');
  perform pg_temp.assert_true(public.canonical_product_code('1237','152747')='152755', 'Mercan high-alcohol case normalizes to single code');
  perform pg_temp.assert_true(public.canonical_product_quantity('1237','152747',1)=24, 'Mercan case-to-single factor is exact 24');

  -- Corona has two physically equal full-case codes; observed sellout main code 152471 is canonical.
  perform pg_temp.assert_true(public.canonical_product_code('1237','152417')='152471', 'equal-size Corona legacy/full code collapses to observed canonical 152471');
  perform pg_temp.assert_true(public.canonical_product_quantity('1237','152417',1)=1, 'equal-size Corona code is one canonical unit');
  perform pg_temp.assert_true(public.canonical_product_quantity('1237','152733',1)=0.25, 'Corona split pack is quarter of canonical unit');

  -- Unknown codes remain identity so products outside paket.xlsx are never silently dropped.
  perform pg_temp.assert_true(public.canonical_product_code('1237','999999')='999999', 'unmapped product code remains identity');
  perform pg_temp.assert_true(public.canonical_product_quantity('1237','999999',3.5)=3.5, 'unmapped quantity remains exact identity');

  -- Every edge must conserve exact canonical quantity under the frozen mapping.
  perform pg_temp.assert_true(not exists (
    select 1
    from public.product_conversion_reference_edges e
    join public.product_canonical_mappings s on s.reference_version_id=e.reference_version_id and s.raw_product_code=e.source_product_code
    join public.product_canonical_mappings t on t.reference_version_id=e.reference_version_id and t.raw_product_code=e.target_product_code
    where e.reference_version_id=v_ref
      and e.source_quantity_basis::numeric*s.canonical_quantity_numerator::numeric*t.canonical_quantity_denominator::numeric
       <> e.target_quantity_basis::numeric*t.canonical_quantity_numerator::numeric*s.canonical_quantity_denominator::numeric
  ), 'all 59 conversion relations must conserve exact canonical quantity');

  -- No standalone Product Master viewer API / technical conversion surface.
  perform pg_temp.assert_true(
    not has_function_privilege('authenticated','public.read_current_product_business_surface()','EXECUTE'),
    'authenticated viewer must not execute deprecated product business surface'
  );
  perform pg_temp.assert_true(
    not has_function_privilege('authenticated','public.read_current_product_domain_summary()','EXECUTE'),
    'authenticated viewer must not execute deprecated product summary surface'
  );
  perform pg_temp.assert_true(
    not has_function_privilege('authenticated','public.resolve_canonical_product(text,text)','EXECUTE')
    and not has_function_privilege('authenticated','public.canonical_product_code(text,text)','EXECUTE')
    and not has_function_privilege('authenticated','public.canonical_product_quantity(text,text,numeric)','EXECUTE')
    and not has_function_privilege('authenticated','public.current_canonical_product_lpu(text)','EXECUTE')
    and not has_function_privilege('authenticated','public.canonical_product_lpu(text,text)','EXECUTE'),
    'canonicalization and LPU helpers are internal calculation infrastructure, not a viewer API'
  );
  perform pg_temp.assert_true(
    not has_function_privilege('authenticated','public.materialize_current_product_domain(text)','EXECUTE'),
    'legacy runtime PRODUCT_CONVERSION materializer must not remain callable after static-reference cutover'
  );

  select count(*) into v_canonical_rows
  from public.product_canonical_mappings m
  where m.reference_version_id=v_ref
    and m.raw_product_code=m.canonical_product_code
    and m.canonical_quantity_numerator=m.canonical_quantity_denominator;
  perform pg_temp.assert_true(v_canonical_rows=36, 'every canonical product has one exact identity row');
end;
$$;

rollback;
