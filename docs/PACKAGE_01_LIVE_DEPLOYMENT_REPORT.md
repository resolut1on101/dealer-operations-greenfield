# Package 01 Live Deployment Report

**Scope:** Package 01 audited migrations `20260809000004` through `20260809000008`, `verify-import-source` Edge Function, and the live frontend release.

**Result:** `PASS / VERIFIED / ACCEPTED`

## Pre-deployment gate

- The explicitly linked target was confirmed as `ncwtlaiormtunpryxjmu` / `dealer-operations-live`, `ACTIVE_HEALTHY`, in `eu-central-1`.
- DEV remained distinct and unlinked: `enlcfbbkfqijspxhngzo` / `dealer-operations-dev`.
- LIVE contained migrations `20260809000000` through `20260809000003`; Package 01 migrations `00004` through `00008` were pending before deployment.
- A fresh linked-LIVE, `public` data-only logical checkpoint was created outside the repository at `C:\secure-backups\dealer-operations-2026-08-09-package01-predeploy.sql` on 2026-08-09 17:35:56 local time. No existing checkpoint was overwritten.
- The same checkpoint passed a local restore rehearsal after clean application of migrations through `20260809000008`.
- Supabase linked-target access, public browser-key retrieval through the project CLI, and Cloudflare OAuth access were available. Secret values were neither logged nor written into repository reports.

## Deployment performed

- `supabase db push --linked` applied, in order:
  - `20260809000004_package_01_import_publication.sql`
  - `20260809000005_package_01_reconciliation_status_fix.sql`
  - `20260809000006_package_01_admin_read_grants.sql`
  - `20260809000007_package_01_audit_fixes.sql`
  - `20260809000008_package_01_storage_update_path_binding.sql`
- `verify-import-source` was deployed to the confirmed LIVE project. The Supabase function inventory reports it as `ACTIVE`, version `1`, with JWT verification enabled.
- The guarded frontend release completed after `npm run verify` passed. Cloudflare Pages returned deployment URL `https://94396efa.dealer-operations-greenfield.pages.dev`; its release environment was built as `live` / `LIVE_TESTING` with database migration version `20260809000008`.

## Post-deployment verification

| Check | Result | Evidence |
|---|---|---|
| LIVE migration history | PASS | Linked migration list now matches local `20260809000000` through `20260809000008`. |
| Package 01 public RLS/admin guard | PASS | Read-only live `public` schema dump confirms `import_batches` RLS, `assert_import_admin`, `create_import_batch`, `reconcile_import_batch`, and `publish_candidate`. |
| Storage policy | PASS | Read-only live `storage` schema dump confirms `source_evidence_admin_insert`, `source_evidence_admin_update`, and `source_evidence_admin_delete`; UPDATE contains the batch-owned `storage_object_path = objects.name` predicate in both `USING` and `WITH CHECK`. |
| Edge Function | PASS | Function inventory shows `verify-import-source` `ACTIVE`; unauthenticated POST returns expected HTTP `401`, proving the deployed JWT boundary is reachable. |
| Frontend HTTP smoke | PASS | The user independently opened the canonical project URL `https://dealer-operations-greenfield.pages.dev` successfully. This is the public release URL and satisfies the frontend smoke requirement. |

## Disposition

The database, RLS/Storage policy, Edge Function, canonical frontend public-smoke evidence, and user acceptance are complete. Package 01 is `VERIFIED / ACCEPTED`. No rollback was performed.

## Reachability Recheck

2026-08-09 additional verification tightened the failure boundary:

- `wrangler pages deployment list --project-name dealer-operations-greenfield` shows a current Production deployment `94396efa-077d-4932-808c-17246213cda9` with URL `https://94396efa.dealer-operations-greenfield.pages.dev`, last updated minutes ago.
- `wrangler pages project list` shows the project domain mapping is the expected default Pages domain `dealer-operations-greenfield.pages.dev`.
- `curl.exe -I -L --max-time 20` to both Pages URLs failed immediately with `Could not connect to server`.
- The same machine also failed to connect to unrelated HTTPS targets such as `https://www.cloudflare.com` and `https://www.google.com`, which indicates the blocker is the local test environment's outbound network path rather than a Pages routing or build artifact defect.

No frontend or deployment configuration change was made in this pass.

## User public-smoke confirmation

- The user confirmed on 2026-08-09 that the canonical project Pages URL `https://dealer-operations-greenfield.pages.dev` opens successfully.
- The hash-specific deployment URL `https://94396efa.dealer-operations-greenfield.pages.dev` did not open for the user. Because the canonical production project URL is reachable, this is a non-blocking deployment-URL observation rather than a release blocker.
- No new deployment or configuration change was performed.
