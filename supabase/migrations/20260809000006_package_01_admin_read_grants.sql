-- Admin read policies are meaningful only when the authenticated API role has SELECT grants.
grant select on public.source_contract_versions, public.import_batches, public.import_chunks, public.staging_rows,
  public.validation_runs, public.validation_issues, public.import_reconciliations, public.candidate_publications
to authenticated;
