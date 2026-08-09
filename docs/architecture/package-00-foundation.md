# Package 00 — Foundation Invariants

## Source of truth

Supabase PostgreSQL is the sole authoritative source for published data. Browser memory, `localStorage`, and IndexedDB may only be transient client caches; they must never establish publication, cross-device state, or official metrics.

## Trust boundaries

- Browser: Supabase publishable key only.
- Database: RLS is the enforcement layer.
- Privileged workflows: version-controlled PostgreSQL RPCs or Edge Functions with explicit validation.
- `service_role`: server/CI secret stores only; never browser code.

## Authorization

Only two application roles exist: `admin` and `viewer`.

- Authenticated users may read explicitly published/read surfaces introduced by later migrations.
- Only `admin` may mutate, validate, publish, override, or administer.
- No capability/scope/feature-permission matrix.

## Migration discipline

- Schema changes are timestamped migrations under `supabase/migrations`.
- Remote environments receive reviewed migrations only through an explicitly verified linked target.
- Never repair production by manual schema editing; use a reviewed forward fix or package-specific rollback/recovery plan.
