# Package 00 — Acceptance Evidence

**Status:** `ACCEPTED`
**User technical approval:** `APPROVED`

## 1. Target repository and reference protection

- Target: `C:\Users\monds\Desktop\YENI\dealer-operations-greenfield`
- `REFERANS_REACT`: `C:\Users\monds\Desktop\YENI\REFERANS`
- `REFERANS_KESAN`: `C:\Users\monds\Desktop\YENI\REFERANS 2\KESAN`

The target is outside both read-only reference paths. Neither reference path contains `.git`, so Git diff/status evidence is unavailable there. Prior read-only inventory evidence: `REFERANS_REACT` = 2,892 files, latest write `2026-08-06 01:39:47 +03:00`; `REFERANS_KESAN` = 21 files, latest write `2026-08-05 21:29:35 +03:00`. Package 00 performed no writes, dependency installs, builds, or application-code generation inside either reference.

## 2. Stack, import direction, and environments

See [`TECH_STACK_DECISION.md`](TECH_STACK_DECISION.md). Supabase/PostgreSQL is the user-selected target; React/Vite was not inherited automatically from the reference app.

Future Package 01 canonical import direction:

**Browser Web Worker parse → chunk/bulk staging → PostgreSQL RPC/set-based validation/reconciliation → candidate publication → atomic publish**

Long XLSX parsing and row-by-row work must not be moved into Edge Functions.

Environment data boundary:

- `local` / `dev`: synthetic or test data only.
- `live`: published business data only.
- First live deployment: Package 00C.

**DEV evidence:** project ref `enlcfbbkfqijspxhngzo` was explicitly linked. `db push --linked` applied all four Package 00 migrations (`20260809000000` through `20260809000003`); `migration list --linked` confirmed all four local and remote versions match. Remote schema queries returned roles `admin,viewer`, policy templates `authenticated_read,admin_write`, and both bootstrap functions. `db query --linked --file supabase/tests/rls-foundation.sql` ran with synthetic users and rolled back at transaction end. No LIVE link or deployment occurred.

## 3. Roles, RLS, and bootstrap

- Only `admin` and `viewer` roles exist; no capability/scope/permission matrix.
- `user_profiles` has no private self-only exception: authenticated users read through `authenticated_read`; only admins mutate through `admin_write`.
- `auth.users` insert creates a deterministic same-UUID `user_profiles` row with default role `viewer`.
- `bootstrap_first_admin(exact_user_uuid)` is restricted to trusted `service_role`; browser clients cannot bootstrap.
- Target-missing fails; same-admin is idempotent; an existing different admin blocks another bootstrap.
- Version-controlled [`supabase/tests/rls-foundation.sql`](supabase/tests/rls-foundation.sql) verifies anon denial, viewer read, viewer mutation/escalation denial, trusted bootstrap, admin read/write, and rejection of roles outside the enum. CI `migration-check` runs this foundation test.
- Runbook: [`docs/runbooks/environment-and-release.md`](docs/runbooks/environment-and-release.md).

## 4. Source of truth and secret/config hygiene

- Runtime code does not use `localStorage`, `indexedDB`, or `sessionStorage` as authoritative state.
- Supabase PostgreSQL is the only official business-data source.
- No `.env`, `.env.local`, or `.env.production` is tracked; only value-free `.env.example` exists.
- `.gitignore` excludes `.env` and `.env.*`, except `.env.example`.
- No real service-role/API/private/Gemini secret or hardcoded Supabase secret was found.
- Production configuration is not derived from local/dev configuration.

## 5. Free-tier baseline

[`FREE_TIER_BASELINE.md`](FREE_TIER_BASELINE.md) records the 2026-08-09 official pricing baseline: 500 MB DB/project, 1 GB Storage, 5 GB egress, 5 GB cached egress, 50 MB maximum upload, two active hosted projects, no automatic backup, and possible pause after one week of inactivity. `dev` + `live` consume the two hosted slots. Limits are not hardcoded into business logic and must be re-verified at deployment time.

## 6. Last local / DEV verification

| Command | Exit | Result |
|---|---:|---|
| `npm ci` | 0 | PASS — 238 packages, 0 vulnerabilities |
| `npm run lint` | 0 | PASS |
| `npm run typecheck` | 0 | PASS |
| `npm test` | 0 | PASS — 2 tests |
| `npm run build` | 0 | PASS |
| `npm run verify` | 0 | PASS |
| `npm run supabase -- db reset --local` | 0 | PASS — 4 migrations applied |
| `npm run test:rls` | 0 | PASS — transactional RLS/bootstrap integration test |
| `npm run supabase -- db query --linked --file supabase/tests/rls-foundation.sql` | 0 | PASS — DEV synthetic/rollback RLS test |

## 7. Git and CI

- Foundation commit: `7465796302ce66db01f873c6392369f12327c7f5`
- Prior acceptance-record commit: `a5d4e3c127cca58b87407f144877b3ca6806b9a4`
- The final closure SHA is reported after commit; this document cannot contain its own final commit hash.
- Remote: `origin https://github.com/resolut1on101/dealer-operations-greenfield.git`; `main` pushed.
- Final HEAD CI evidence is verified after this acceptance record is committed and is reported with the final closure SHA and run URL.
- Required final jobs: `quality = PASS`, `migration-check = PASS`.

## 8. Review-bundle safety

`npm run review:zip` is designed to archive only clean, committed tracked files using `git archive HEAD`.

Preflight rejects runtime/generated paths including `.git/`, `node_modules/`, `dist/`, `coverage/`, `playwright-report/`, `test-results/`, `.env*` except empty `.env.example`, `supabase/.temp/`, cache/temp, and logs. It also scans for private keys, JWT-like values, and non-empty privileged secret assignments; any finding blocks ZIP creation.

- Review Bundle: `PASS`
- Secret Scan: `PASS`
- Excluded Runtime: `PASS`

## 9. External data reference

Future Package 01 external read-only data reference:

`C:\Users\monds\Desktop\YENI\VERI_REFERANS`

See [`docs/architecture/data-reference-boundary.md`](docs/architecture/data-reference-boundary.md). This record does not implement an import engine, parser, import table, or fixture generation.

## Open blockers

None. The user explicitly approved the technical stack and architecture before Package 00 closure.
