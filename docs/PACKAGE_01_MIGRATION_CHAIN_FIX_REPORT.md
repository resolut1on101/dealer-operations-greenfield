# Package 01 Migration-Chain Fix Report

**Scope:** Repair the clean-sequence function-signature defect in `20260809000007_package_01_audit_fixes.sql` only. No live deployment, Package 01U work, RLS-semantic change, publication-behavior change, or new feature was performed.

**Result:** `PASS`

## Correction

Migration `20260809000004` defines `public.create_import_batch` with nine parameters:

`(uuid, text, text, jsonb, text, bigint, bigint, integer, jsonb)`.

Migration `20260809000007` incorrectly used a non-existent ten-parameter signature for its unconditional `DROP FUNCTION`. The correction:

- replaces that statement with `DROP FUNCTION IF EXISTS` using the actual nine-parameter signature;
- aligns the subsequent `REVOKE` and `GRANT` statements with that same signature.

The replacement function body, grants to other objects, RLS policies, Storage policies, and publication logic are unchanged. `IF EXISTS` makes the replacement safe when the expected predecessor is absent; `CREATE OR REPLACE` retains the intended clean-sequence and direct-replay behavior. An already-upgraded database does not replay an applied migration, so its existing function behavior is not altered by this source correction.

## Verification

All commands completed locally on 2026-08-09:

| Command | Result | Evidence |
|---|---|---|
| `npm.cmd run supabase -- db reset --local` | PASS | Clean database applied migrations `20260809000000` through `20260809000008` in order, including `00007` and `00008`. |
| `npm.cmd run restore:rehearsal -- --environment local --input C:\secure-backups\dealer-operations-2026-08-09.sql` | PASS | Reset reapplied the complete chain; the logical checkpoint restored into local and the Package 00 identity-table check passed. |
| `npm.cmd run test:import` | PASS | Package 01 import integration, including AUD-01 through AUD-04, failed-publish preservation, and mutation-boundary regression coverage. |
| `npm.cmd run test:import:concurrency` | PASS | One active publication and stale concurrent publisher rejection. |
| `npm.cmd run verify` | PASS | Lint, typecheck, workspace tests, and production build passed. |

## Disposition

The migration-chain blocker is resolved locally. This report does not authorize or perform live deployment; the separate live-deployment gate must be repeated before any production change. Package 01 remains unaccepted pending its required live deployment and UAT.
