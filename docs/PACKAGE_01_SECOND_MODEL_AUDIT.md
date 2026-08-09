# Package 01 Narrow Second-Model Audit

**Scope:** idempotency, reconciliation, atomic publication, concurrency, RLS/admin mutations, failed-publish preservation, and chunk integrity only.

**Result:** `BLOCKED — NOT PASS`

## Critical blocker

### AUD-01 — Source-contract versions are mutable after use

`register_source_contract` performs an `ON CONFLICT (source_kind, version) DO UPDATE` of the sheet, headers, required fields, control-total fields, and publication mode. Existing batches and validation runs reference that same row by `source_contract_version_id`; validation and reconciliation reread the mutable row. A later contract registration can therefore change the rules used by an already validated/reconciled candidate, and `publish_candidate` does not verify that the contract definition is unchanged.

This breaks immutable provenance and the requirement that a source-contract **version** binds the import/publication. It is a release blocker.

Evidence: `supabase/migrations/20260809000004_package_01_import_publication.sql`, lines 176–190, 289, 332, and 372–404.

## High findings

### AUD-02 — Reconciliation retry is not idempotent

The batch stores `reconciliation_id` as a foreign key to `import_reconciliations`. A repeated `reconcile_import_batch` first deletes the reconciliation for that batch, but the batch still references it. With the default `NO ACTION` foreign-key behavior, the delete fails. The normal retry/resume contract therefore cannot safely repeat this stage.

Evidence: migration lines 341–351 and the `import_batches_reconciliation_fk` constraint.

### AUD-03 — Client-declared chunk hash is not verified against staged content

`stage_import_chunk` calculates `server_chunk_hash` from the JSON payload, but it accepts any `p_chunk_hash` on the first submission. The declared `chunk_hash` in the required idempotency tuple is only compared on a later retry; it is not required to equal the content digest. This weakens the stated chunk-integrity commitment and auditability.

Evidence: migration lines 245–274.

### AUD-04 — Storage object path is client supplied rather than server generated

`create_import_batch` accepts and persists `p_storage_object_path` directly, and the verification function downloads exactly that path. There is no server-generated batch/object identity or path-format enforcement. This does not meet the binding source-evidence path rule and weakens provenance isolation.

Evidence: migration lines 195–218 and `supabase/functions/verify-import-source/index.ts`.

## Controls that passed this audit

- Publication switch is transactionally serialized by a source+scope advisory lock and an expected active-publication check.
- A stale concurrent publisher is rejected; the local two-session test covers the one-active-publication outcome.
- Failed/stale publication leaves the previous publication head unchanged in the local integration test.
- Mutation RPCs call the admin assertion and direct table writes are not granted to authenticated users; published read surfaces remain separately readable.
- A repeated identical chunk returns the existing chunk, while conflicting content for the same chunk number is rejected.

## Required disposition

Do not begin live deploy preparation. Resolve AUD-01 through AUD-04, add focused regression tests for each, then repeat this narrow audit. Package 01 remains `AUTOMATED_TESTS_PASSED / NOT_DEPLOYED / AWAITING_USER_ACCEPTANCE`, not `AUDIT_PASS` or `ACCEPTED`.
