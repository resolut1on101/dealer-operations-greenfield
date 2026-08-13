# Package 01 Implementation Report — Reliable High-Volume Import and Publication Engine

**Status:** `VERIFIED / ACCEPTED`
**Scope:** Package 01 only. Package 01U UI and all domain adapters remain out of scope.

## Delivered

- Private `source-evidence` Storage bucket and an Edge Function that server-hashes the stored object before staging. The function is an orchestration/security boundary only; it does not parse XLSX.
- Versioned, contract-driven source recognition using required sheet and headers. No filename recognition or domain parser was added.
- Idempotent `import_batches`, `import_chunks`, and set-based `staging_rows` RPC flow. A repeated chunk with identical batch, number, offset, declared hash, row count, and server-calculated payload digest returns the original chunk; a conflicting retry fails.
- Set-based validation for required fields, explicitly excluded rows, duplicate payloads, and configured exact-decimal control-total fields.
- Exact reconciliation gate: `parsed = valid + excluded + blocked + duplicate`, expected chunks/rows, and contract-defined control totals must match before a candidate can be created.
- Candidate and versioned publication tables with a source+scope advisory lock, optimistic expected-active-pointer check, atomic head switch, and publication-level notification. A failed or stale publish leaves the previous active publication intact.
- Admin-only mutations and authenticated published-read access. Browser code has only a worker protocol/chunking contract; no upload UI, per-row request loop, or browser secret was introduced.

## Automated evidence

| Command | Result | Coverage |
|---|---|---|
| `npm.cmd run verify` | PASS | lint, TypeScript, unit tests, production build |
| `npm.cmd run test:import` | PASS | migration behavior, chunk retry/idempotency, duplicate conflict, validation, exact reconciliation, failed-publish preservation, RLS |
| `npm.cmd run test:import:concurrency` | PASS | two concurrent publishers yield one active version; stale writer is rejected |
| `npm.cmd run test:import:load` | PASS | set-based 1K chunks, reconciliation, candidate creation, and publication for 2.5K/10K/25K/50K synthetic batches |

Synthetic local measurements (Docker/PostgreSQL, test transaction rolled back):

| Rows | Chunks | Elapsed |
|---:|---:|---:|
| 2,500 | 3 | 0.838 s |
| 10,000 | 10 | 9.621 s |
| 25,000 | 25 | 2.492 s |
| 50,000 | 50 | 5.828 s |

The 10K measurement includes local runtime variability and is retained as observed evidence, not a performance guarantee. No per-row HTTP or per-row database mutation is used by the Package 01 transport contract.

## Acceptance status

Package 01 live deployment and required user acceptance are complete. The package is `VERIFIED / ACCEPTED`; see `docs/PACKAGE_01_ACCEPTANCE.md` for the acceptance record.