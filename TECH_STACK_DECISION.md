# Package 00 — Technical Stack Decision

**Decision date:** 2026-08-09  
**Scope:** Greenfield technical foundation only; excludes business domain, import engine, and D0 design.

## Selected stack

- **Frontend:** React 19, TypeScript, Vite, React Router, TanStack Query, Zod.
- **Backend/API:** No permanently running standalone Node API. Standard reads use Supabase RLS-protected APIs. Trusted mutations, publish workflows, and later privileged operations use version-controlled PostgreSQL RPCs and, only where appropriate, Supabase Edge Functions.
- **Data:** Supabase PostgreSQL is the sole authoritative source of truth. Supabase also provides Auth and Storage.
- **Deployment:** Static frontend on Cloudflare Pages; separate Supabase `dev` and `live` projects. Package 00 has no live deployment; the first live release is Package 00C.

**Supabase/PostgreSQL is a user-selected target.** React/Vite was independently evaluated and is not inherited automatically from the legacy React reference.

## Why this stack

React/Vite fits an SPA with dense tables and read-heavy operational screens without introducing an unnecessary SSR/server runtime. TypeScript tooling is mature and the build/runtime surface stays small. Supabase PostgreSQL provides RLS, migrations, Auth, Storage, and cross-device consistency in one managed data platform.

The browser receives only a publishable key. `service_role` and other privileged secrets never enter client bundles. Browser cache is never authoritative; published data and metrics come from PostgreSQL.

## Alternatives considered

| Alternative | Advantage | Why not selected |
|---|---|---|
| Next.js + SSR + route handlers | SSR and server routes in one framework | No current SSR need; increases runtime/deployment/secret complexity. |
| React SPA + Node/NestJS API + managed PostgreSQL | Maximum backend control | Adds auth, storage, policy-equivalent enforcement, hosting, and operational cost. |
| Cloudflare Workers + D1 | Simple edge APIs | Poorer fit for PostgreSQL compatibility, transactional finance/integrity, and later bulk workloads. |
| **Supabase + React/Vite** | PostgreSQL, RLS, Auth, Storage, local CLI, low operations | Provider limits, inactivity, and backup constraints require explicit runbooks. |

## High-volume import boundary

Package 00 does not implement imports. Package 01 must use this canonical direction for 10K/25K/50K XLSX workloads:

**Browser Web Worker parse → chunk/bulk staging → PostgreSQL RPC/set-based validation and reconciliation → candidate publication → atomic publish**

Hard constraints:

- Do not perform long XLSX parsing inside Edge Functions by default.
- Edge Functions may provide trusted orchestration/security boundaries, not row-by-row XLSX processing.
- No per-row HTTP calls or per-row transactions.
- Do not render tens of thousands of browser DOM rows; use aggregate reads and paginated/keyset drill-downs.
- The stack must support Web Workers, Storage evidence, SQL bulk/RPC operations, keyset pagination, and aggregate read models.

## Free-tier impact

Static frontend hosting avoids a dedicated application-server cost. Supabase Free capacity requires careful control of database copies, Storage evidence, and egress. Provider limits are **not** business logic; they are planning, System Health, and deployment-time validation inputs.

See [`FREE_TIER_BASELINE.md`](FREE_TIER_BASELINE.md).

## User technical approval

**USER TECHNICAL APPROVAL: APPROVED**

Approved explicitly by the user before Package 00 closure.
