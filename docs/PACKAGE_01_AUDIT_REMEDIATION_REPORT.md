# Package 01 Narrow Audit Remediation Report

**Scope:** AUD-01 through AUD-04 only. No UI, new domain feature, Package 01U work, or live deployment was performed.

**Result:** `AUD REMEDIATION PASS / NOT DEPLOYED / AWAITING USER ACCEPTANCE`

| Audit item | Disposition | Remediation and focused evidence |
|---|---|---|
| AUD-01 — mutable source-contract version | RESOLVED | Same `source_kind + version` may now be registered idempotently only when every definition field is identical; different content fails and requires a new version. A database trigger also rejects direct definition mutation after a batch uses the contract. `test:import` covers both paths. |
| AUD-02 — reconciliation retry FK failure | RESOLVED | `reconcile_import_batch` returns the persisted `reconciliation_id` when one exists and no longer deletes it. A repeated call returns the same ID in `test:import`. |
| AUD-03 — unverified client chunk hash | RESOLVED | The server canonicalizes the JSON payload and requires the declared hash to equal its SHA-256 digest before any staging write. The worker uses the same canonical key ordering. `test:import` proves a wrong first-submission hash is rejected, then verifies the normal retry path. |
| AUD-04 — client-selected Storage path | RESOLVED | `create_import_batch` no longer accepts an object path. It allocates the batch UUID and persists only `imports/<batch_id>/source.xlsx`; a database constraint and Storage RLS write policies enforce that binding. `test:import` verifies the generated path. |

## Regression results

- `npm.cmd run verify` — PASS
- `npm.cmd run test:import` — PASS, including AUD-01/AUD-02/AUD-03/AUD-04 focused cases
- `npm.cmd run test:import:load` — PASS for 2.5K, 10K, 25K, and 50K synthetic batches
- `npm.cmd run test:import:concurrency` — PASS; one active publication and stale writer rejected

## Changed files

- `supabase/migrations/20260809000004_package_01_import_publication.sql`
- `supabase/migrations/20260809000007_package_01_audit_fixes.sql`
- `supabase/tests/package-01-import.sql`
- `supabase/tests/package-01-synthetic-load.sql`
- `scripts/test-package-01-publication-concurrency.mjs`
- `apps/web/src/workers/import-chunk.worker.ts`
- `docs/PACKAGE_01_AUDIT_REMEDIATION_REPORT.md`

The local Supabase migration was applied only to the local development database. Live deployment preparation was not started. Package 01 remains unaccepted until the required live deployment and user acceptance protocol are completed.
