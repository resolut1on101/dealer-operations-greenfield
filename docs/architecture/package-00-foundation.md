# Paket 00 Teknik Temel Kararı

## Source of truth

Supabase PostgreSQL is the sole authoritative source for published data. Browser memory, localStorage and IndexedDB may only be transient client caches; they must never establish publication, cross-device state or official metrics.

## Trust boundaries

- The browser uses the Supabase publishable key only.
- RLS is the database enforcement layer.
- Trusted mutations and later privileged workflows run through version-controlled Edge Functions or database RPCs with explicit validation.
- The `service_role` key is never sent to the browser and is only configured in hosted function/CI secret stores.

## Authorization model

The only application roles are `admin` and `viewer`.

- Authenticated users may read explicitly published/read surfaces when later migrations introduce them.
- Only `admin` may mutate, validate, publish or administer.
- No feature-level capability model is allowed.

## Versioning

Schema changes are timestamped migrations in `supabase/migrations`. A remote environment receives only reviewed migrations through an explicit linked-target command. A failed production migration uses a reviewed forward fix or the package-specific rollback plan; the schema is not edited manually.
