# Dealer Operations Greenfield

Independent greenfield application repository. The two legacy applications are **read-only references**, never dependencies or implementation targets.

## Start here — minimal agent context

Do **not** scan every Markdown file for every task. Read:

1. `README.md`
2. [`docs/AGENT_CONTEXT_MAP.md`](docs/AGENT_CONTEXT_MAP.md)
3. Only the package-specific documents listed there.

This is the default context-loading rule for Luna, Terra, reviewers, and any coding agent unless an audit explicitly requires broader evidence.

## Technical artifact language

All new agent-authored technical artifacts are **English by default**: package reports, acceptance/audit evidence, architecture notes, runbooks, change logs, appendices, test evidence, implementation notes, and agent handoff/context files. Keep machine statuses such as `PASS`, `FAIL`, `BLOCKED`, `REVIEW_REQUIRED`, and `ACCEPTED` unchanged.

User-facing UAT/test cards and direct instructions to the user may remain **Turkish**. Preserve literal external filenames, folder names, database identifiers, source-system labels, and Windows paths exactly when they are contracts/evidence; do not translate them merely for language consistency.

## Repository boundary

- Target repository: `C:\Users\monds\Desktop\YENI\dealer-operations-greenfield`
- React reference: `C:\Users\monds\Desktop\YENI\REFERANS`
- Keşan reference: `C:\Users\monds\Desktop\YENI\REFERANS 2\KESAN`
- External real-data reference: `C:\Users\monds\Desktop\YENI\VERI_REFERANS`

The reference applications and `VERI_REFERANS` remain outside this repository. Never modify, install dependencies into, build inside, normalize, or overwrite those source locations unless a later explicitly approved task says otherwise.

## Package 00 boundary

Package 00 establishes only the technical foundation: workspace, environment isolation, role/RLS foundation, migration discipline, test tooling, CI, and release safety. It contains **no** business domain, import engine, metric formula, AI feature, product navigation, or D0 visual design.

## Prerequisites

- Node.js 22+
- Docker Desktop with WSL2, or another Docker-compatible runtime, for local Supabase
- Separate hosted Supabase projects for `dev` and later `live`

## First local run

1. Copy `.env.example` to `.env.local`; add the local Supabase URL and publishable key.
2. `npm install`
3. `npm run supabase -- start`
4. `npm run dev --workspace @dealer-operations/web`

This project uses local Supabase ports `55321`–`55325` to avoid common default-port conflicts. Never expose the local Supabase stack to external traffic.

## Environment contract

| Environment | Purpose | Data |
|---|---|---|
| `local` | Development and automated tests | Synthetic only |
| `dev` | Shared integration testing | Synthetic/test only |
| `live` | User-facing releases beginning with Package 00C | Published business data |

Before any deployment, follow [`docs/runbooks/environment-and-release.md`](docs/runbooks/environment-and-release.md). Before the first live release, also follow [`docs/runbooks/backup-restore.md`](docs/runbooks/backup-restore.md).
