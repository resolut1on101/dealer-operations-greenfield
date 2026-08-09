# Agent Context Map

Goal: reduce Codex/agent context use without losing binding rules.

## Default loading rule

Read only: `README.md` → this file → package-specific docs below → directly relevant code. Expand only for explicit audits or unresolved cross-package dependencies.

| Work | Required Markdown |
|---|---|
| Package 00 foundation | `TECH_STACK_DECISION.md`; `docs/architecture/package-00-foundation.md`; `docs/runbooks/environment-and-release.md` |
| Package 00 acceptance/review | `PACKAGE_00_ACCEPTANCE.md` + only documents cited by disputed evidence |
| Package 00C live release | `docs/runbooks/environment-and-release.md`; `docs/runbooks/backup-restore.md`; `FREE_TIER_BASELINE.md` |
| Package 01 import | `TECH_STACK_DECISION.md` import section; `docs/architecture/data-reference-boundary.md`; `FREE_TIER_BASELINE.md` only when capacity matters |
| Auth/RLS | foundation architecture + environment runbook + relevant migration/test SQL |
| CI/review ZIP | acceptance Git/CI + Review Bundle sections; `scripts/create-review-zip.mjs` |

External references (use only when assigned): `C:\Users\monds\Desktop\YENI\REFERANS`, `C:\Users\monds\Desktop\YENI\REFERANS 2\KESAN`, `C:\Users\monds\Desktop\YENI\VERI_REFERANS`. All remain read-only/outside repo.

## Efficiency rules

- Prefer exact headings/ranges; do not reread whole long docs unnecessarily.
- Never load generated ZIPs, build output, `node_modules`, `.temp`, logs, or caches as context.
- Put stable rules in authoritative docs; package prompts contain only deltas + acceptance criteria.
- Acceptance reports contain evidence/blockers, not full architecture restatements.
- Surface document conflicts; never silently reconcile or invent rules.
- **Artifact language contract:** all new technical reports, acceptance/audit files, architecture/runbook additions, appendices, evidence notes, change logs, and agent handoffs are English. User-facing UAT/test cards and direct user instructions may stay Turkish. Preserve literal source filenames/paths/identifiers exactly.
- Keep package prompts delta-only: do not restate stable architecture or policy already linked here.
- Prefer tables, bullets, IDs, and explicit acceptance criteria over repeated narrative prose.
- Reference authoritative sections by path/heading instead of copying them into new reports.
