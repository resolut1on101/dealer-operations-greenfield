# Dealer Operations Greenfield

This repository is the new, independent application. `REFERANS` and `REFERANS 2/KESAN` are not dependencies and are never modified by this repository.

## Package 00 boundary

This package establishes only the workspace, environment separation, role foundation, migration discipline, test tooling and CI. It deliberately contains no business domain, import engine, metric formula, AI feature, product navigation or D0 visual design.

## Prerequisites

- Node.js 22+
- Docker Desktop with WSL2 (or another Docker-compatible runtime) for local Supabase
- A separate Supabase project for `dev`, later a separate project for `live`

## First local run

1. Copy `.env.example` to `.env.local` and fill the local Supabase URL and publishable key. This project deliberately uses the `55321`–`55325` local port range so it does not interfere with another local Supabase project using the defaults.
2. Run `npm install`.
3. Run `npm run supabase -- start`.
4. Run `npm run dev --workspace @dealer-operations/web`.

The local Supabase stack must never be exposed to external traffic. Migrations are version-controlled and are applied locally before a linked dev/live environment.

## Environment contract

| Environment | Purpose | Data |
|---|---|---|
| local | Development and automated tests | synthetic only |
| dev | Shared integration testing | synthetic/test only |
| live | User-facing releases from Package 00C | published business data |

See `docs/runbooks/environment-and-release.md` and `docs/runbooks/backup-restore.md` before deploying.
