# Package 00 Acceptance Evidence

**Status:** `REVIEW_REQUIRED`
**User technical approval:** `PENDING`

## Target repository and reference protection

- **Target repository:** `C:\Users\monds\Desktop\YENI\dealer-operations-greenfield`
- **REFERANS_REACT:** `C:\Users\monds\Desktop\YENI\REFERANS`
- **REFERANS_KESAN:** `C:\Users\monds\Desktop\YENI\REFERANS 2\KESAN`

The target repository is separate from both READ-ONLY reference paths. Neither reference path has a `.git` directory, so `git status` and `git diff` cannot be applied there. Earlier read-only inventory evidence: REFERANS_REACT had 2,892 files, last modified `2026-08-06 01:39:47 +03:00`; REFERANS_KESAN had 21 files, last modified `2026-08-05 21:29:35 +03:00`. No writes, dependency installation, builds, or application-code generation were performed in either reference during Package 00.

## Stack, import direction, and environments

The selected stack and alternative assessment are in [TECH_STACK_DECISION.md](TECH_STACK_DECISION.md). Supabase/PostgreSQL is the user-selected target; React/Vite was not automatically inherited from a reference. Package 01's canonical import direction is Browser Web Worker parse → chunk/bulk staging → PostgreSQL RPC/set-based validation/reconciliation → candidate publication → atomic publish. Long XLSX parsing and per-row work do not move into an Edge Function.

`local` and `dev` contain synthetic/test data only; `live` contains published business data only. No real customer, sellout, or financial data was seeded in Package 00. `local` is a Docker instance; separate hosted Supabase projects and secrets are required for `dev` and `live`. The first live deployment is in Package 00C.

**DEV verification:** explicit project ref `enlcfbbkfqijspxhngzo` was linked. Three Package 00 migrations were applied with `db push --linked`; a remote-schema query returned three migrations, `admin,viewer`, `authenticated_read,admin_write`, and two bootstrap functions. `db query --linked --file supabase/tests/rls-foundation.sql` ran with synthetic test users and rolled back at the end of the transaction. No LIVE connection or deployment was made.

## Roles, RLS, and admin bootstrap

- The contract/migrations define only the `admin` and `viewer` roles; there is no capability, scope, or permission matrix.
- `user_profiles` is not a business/read model. There is no special “read only one's own profile” exception: authenticated users can read through `authenticated_read`, and only an admin can mutate through `admin_write`. No customer- or representative-based restriction was added to the business-read side.
- The `auth.users` insert trigger creates a deterministic `user_profiles` record with the same UUID and the default `viewer` role.
- `bootstrap_first_admin(exact_user_uuid)` is available only to trusted `service_role` calls; the browser does not hold a service role. It errors when the target profile is missing, is idempotent for the same admin, and errors when another admin exists. See [environment-and-release.md](docs/runbooks/environment-and-release.md).
- Version-controlled [rls-foundation.sql](supabase/tests/rls-foundation.sql) verifies denied anon reads/writes; denied viewer mutations/escalation; trusted bootstrap; admin reads/writes; and rejection of enum values other than `admin`/`viewer`. It also runs in the CI `migration-check` job.

## Source of truth and secret/configuration boundary

- Runtime code does not use `localStorage`, `indexedDB`, or `sessionStorage`; they appear only as prohibited principles in two architecture/acceptance documents.
- Supabase PostgreSQL is the sole official source of business data.
- `.env`, `.env.local`, and `.env.production` are absent; only the valueless `.env.example` exists. `.gitignore` includes `.env`, `.env.*`, and `!.env.example`.
- No real service-role/API/private/Gemini-like secret or hard-coded Supabase secret was found. The production target is not derived from local/dev configuration.

## Free-tier verification

[FREE_TIER_BASELINE.md](FREE_TIER_BASELINE.md) was verified against the official [Supabase pricing](https://supabase.com/pricing) source on 2026-08-09: 500 MB database per project, 1 GB Storage, 5 GB egress, 5 GB cached egress, 50 MB maximum file upload, two active hosted projects, no automatic backup, and pause after one week of inactivity. The two hosted-project slots are for dev+live; limits are not hard-coded into business logic and are reverified during deployment.

## Latest local verification

| Command | Exit | Result |
|---|---:|---|
| `npm ci` | 0 | PASS — 238 packages, 0 vulnerabilities |
| `npm run lint` | 0 | PASS |
| `npm run typecheck` | 0 | PASS |
| `npm test` | 0 | PASS — 2 tests |
| `npm run build` | 0 | PASS |
| `npm run verify` | 0 | PASS |
| `npm run supabase -- db reset --local` | 0 | PASS — 3 migrations applied |
| `npm run test:rls` | 0 | PASS — RLS/bootstrap integration test with transaction rollback |
| `npm run supabase -- db query --linked --file supabase/tests/rls-foundation.sql` | 0 | PASS — synthetic/rollback RLS test against DEV |

## First-admin concurrency

**Current verification note (2026-08-09):** the explicit DEV project `enlcfbbkfqijspxhngzo` now has all four Package 00 migrations. `migration list --linked` confirmed local and remote versions `20260809000000` through `20260809000003` match. The version-controlled synthetic, transaction-rollback `rls-foundation.sql` test passed on DEV. No token is stored in this repository, and no LIVE target is touched. User technical stack approval is still pending.

- Migration `20260809000003_first_admin_global_lock.sql` makes `bootstrap_first_admin(exact_user_uuid)` acquire a deterministic transaction-scoped PostgreSQL advisory lock before it inspects or mutates `user_profiles`.
- The version-controlled `scripts/test-first-admin-concurrency.mjs` test is invoked by `npm run test:rls` and therefore by CI's `migration-check` job after a local reset. It opens two independent database sessions for two different UUID targets. The first session wins; the second waits for the global lock, observes the newly-created admin, and fails. The test asserts the final roles are exactly one `admin` and one `viewer`.
- Local result after the four Package 00 migrations: `PASS` — `Concurrent first-admin bootstrap PASS: two independent DB sessions produced one admin and one rejected call.`

## Git and CI

- Concurrency foundation verification commit: `487596efdffb458ae6485e28db2086e05286cc9e`.
- GitHub Actions [CI run #4](https://github.com/resolut1on101/dealer-operations-greenfield/actions/runs/31306505864) for that commit: `quality = success`, `migration-check = success` (including the clean reset and two-session concurrency test).
- The safe review archive is regenerated only with `npm run review:zip` from a clean `HEAD`; its filename embeds the exact archived `HEAD` SHA. It is a git-archive output, not a working-directory ZIP, and is ignored by Git.
- Foundation commit: `7465796302ce66db01f873c6392369f12327c7f5`.
- Previous acceptance-record commit: `a5d4e3c127cca58b87407f144877b3ca6806b9a4`.
- This update's closing SHA is provided in the external closing message after its commit is created; a document cannot contain its own commit hash.
- Remote: `origin https://github.com/resolut1on101/dealer-operations-greenfield.git`; `main` was pushed.
- GitHub Actions [CI run #1](https://github.com/resolut1on101/dealer-operations-greenfield/actions/runs/31305308577): `quality = success`, `migration-check = success`. **CI: PASS.**

## Review-bundle safety

- `npm run review:zip` produces a ZIP with `git archive HEAD` from clean, committed tracked files only; the working directory is never archived directly.
- Before ZIP creation, tracked-path checks reject `.git/`, `node_modules/`, `dist/`, `coverage/`, `playwright-report/`, `test-results/`, `.env`, `.env.*` (except the empty `.env.example` template), `supabase/.temp/`, and cache/temp/log paths.
- The same precheck scans for private keys, JWT-like values, and non-empty service-role/API/private/Gemini/OpenAI secret assignments; it refuses to create the ZIP if it finds one. The review bundle exposes the commit SHA through this document but does not include `.git`.
- Review Bundle: `PASS` (the mechanism was run and its content was verified); Secret Scan: `PASS`; Excluded Runtime: `PASS`.

## External data reference

The external READ-ONLY data-reference structure for future Package 01 use is recorded as `C:\Users\monds\Desktop\YENI\VERI_REFERANS`. Its directory contract and real-Excel protection rules are in [data-reference-boundary.md](docs/architecture/data-reference-boundary.md). This record does not create an import engine, parser, database import table, or fixtures.

## Open blockers

1. User technical stack approval.
