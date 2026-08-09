# Package 01 AUD-04 Storage UPDATE Remediation Report

**Scope:** AUD-04 Storage UPDATE path binding only.

**Result:** `RESOLVED / NOT DEPLOYED / AWAITING USER ACCEPTANCE`

`source_evidence_admin_update` now applies the same batch-owned, unverified, server-generated path predicate in both `USING` and `WITH CHECK`. The post-update `storage.objects.name` must therefore equal the authenticated batch owner's `storage_object_path`; a rename to an arbitrary/unbound path is rejected.

## Focused regression evidence

- `npm.cmd run test:import` — PASS
  - inserts a valid object at the generated batch path;
  - proves rename to `client-controlled/unbound.xlsx` is denied;
  - proves a metadata update that preserves the valid bound path succeeds.
- `npm.cmd run test:import:concurrency` — PASS
- `npm.cmd run verify` — PASS

## Changed files

- `supabase/migrations/20260809000008_package_01_storage_update_path_binding.sql`
- `supabase/tests/package-01-import.sql`
- `docs/PACKAGE_01_AUD04_STORAGE_REMEDIATION_REPORT.md`

The migration was applied only to the local Supabase database. No live deployment, UI work, or new feature work was performed.
