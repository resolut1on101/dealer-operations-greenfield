# Environment and Release Runbook

## Isolation

`local`, `dev`, and `live` use distinct Supabase instances/projects and secrets. Every remote command must explicitly identify and verify its target; never infer `live` from a default link. `local` and `dev` contain synthetic/test data only; `live` is reserved for published business data.

## Local and dev validation

1. Start Docker-compatible local Supabase and run `npm run supabase -- db reset --local`.
2. Run `npm run verify` and `npm run test:rls`.
3. For dev, explicitly link the dev project, confirm its project ref, apply migrations, and run the version-controlled RLS test using synthetic users only.
4. Do not use a live target as the first environment for a migration, build, or authentication test.

## First admin bootstrap

1. Create the login users through normal Supabase Auth. The trigger creates each matching `public.user_profiles` record with `viewer` role.
2. Obtain the exact Auth UUID from the approved identity source; never infer it from an email address.
3. Trusted server-side `service_role` only: `select public.bootstrap_first_admin('<exact-user-uuid>');`.
4. Test bootstrap locally first. Remote dev/live bootstrap requires the exact UUID and an explicitly verified target.
5. Never expose `service_role` in browser bundles, `.env.example`, Cloudflare build variables, or logs.

## First live release (Package 00C)

1. Complete the backup checkpoint and local restore rehearsal in `backup-restore.md`.
2. In Cloudflare Pages, set only public build variables: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_APP_ENV=live`, `VITE_RELEASE_PACKAGE=00C`, `VITE_RELEASE_STATE=LIVE_TESTING`, `VITE_BUILD_VERSION=<commit-sha>`, and `VITE_DB_MIGRATION_VERSION=<latest-migration>`.
3. Configure the live Supabase Auth Site URL and redirect URLs to the final Cloudflare Pages URL.
4. Authenticate the deploy operator with an operator-only `CLOUDFLARE_API_TOKEN` outside the repository, or an interactive `npx wrangler login` session. It is not a frontend variable.
5. Run `npm run deploy:live`. The command repeats `npm run verify`, builds the static frontend, then publishes `apps/web/dist` to the `dealer-operations-greenfield` Cloudflare Pages project.
6. Record the deployed URL, build/version, migration version, and release state. The UI must show `LIVE_TESTING` until the user gives Package 00C PASS.

## After user acceptance

After every mandatory Package 00C user test passes, redeploy the same code with `VITE_RELEASE_STATE=VERIFIED`, then record user acceptance. Do not use `ACCEPTED` as a client-side release state; `ACCEPTED` is the package-closeout status.
