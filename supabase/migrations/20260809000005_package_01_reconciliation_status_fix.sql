-- Keeps already-migrated local/dev environments aligned with Package 01's enum-safe reconciliation status update.
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
