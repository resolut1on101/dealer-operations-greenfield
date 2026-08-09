# Environment and Release Runbook

## Isolation

`local`, `dev`, and `live` use distinct Supabase instances/projects and secrets. Every remote command must explicitly identify/verify its target; never infer `live` from a default link.

## Local

1. Start Docker-compatible runtime.
2. `npm run supabase -- start`
3. Put reported local URL + publishable key in `.env.local`.
4. `npm run supabase -- db reset --local` to validate clean migrations.

## Dev / live

1. Explicitly link the intended project ref.
2. Verify environment identity, migration list, and backup-checkpoint requirement.
3. Run required local/CI checks.
4. Push migrations only to the verified target.
5. Deploy the static web build with matching environment variables.

User-facing release records start in **Package 00C**; Package 00 has no user-facing live deploy.

## First-admin bootstrap

1. Create user through normal Auth; `auth.users` insert creates same-UUID `public.user_profiles` with role `viewer`.
2. Obtain the **exact Auth UUID** from the user/approved identity source; never guess by email/name.
3. Trusted server-side `service_role` only: `select public.bootstrap_first_admin('<exact-user-uuid>');`
4. Never expose `service_role` in browser bundles, `.env.example`, or client variables.
5. Missing target fails; same existing admin is idempotent; a different existing admin blocks another bootstrap.
6. Test locally first. Real `dev`/`live` bootstrap requires explicit user-provided UUID + target and explicit remote link.
7. Authenticated browser users read through `authenticated_read`; they cannot change roles. `admin_write` is for an existing admin only.
