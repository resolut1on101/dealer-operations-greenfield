# Environment and Release Runbook

## Environment isolation

`local`, `dev` and `live` use distinct Supabase projects/instances and distinct environment files/secrets. A command targeting a remote project must name its target explicitly; no script may infer `live` from a default link.

## Local

1. Start a Docker-compatible runtime.
2. Run `npm run supabase -- start`.
3. Copy the reported local URL and publishable key to `.env.local`.
4. Run `npm run supabase -- db reset --local` to validate all migrations from a clean database.

## Dev and live

1. Link the intended remote project explicitly with its project ref.
2. Verify the environment name, migration list and backup checkpoint requirement.
3. Run the CI checks locally/through CI.
4. Push migrations only to the verified target.
5. Deploy the static web build with the matching environment variables.

Live deployment and package release-state records begin in Package 00C. Package 00 does not deploy a user-facing application.
