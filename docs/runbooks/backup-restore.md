# Backup, Restore, and Release-Recovery Runbook

## Scope and boundaries

This is the Package 00C minimum logical-recovery procedure. The logical checkpoint is `public` **data only**; its schema is reconstructed from the version-controlled migrations. Supabase Storage is a separate source-file inventory and must be checked separately. Never rely on a downloadable managed backup on a Free plan.

The procedure is intentionally explicit. A logical dump is created from the named live project and restored only into local/dev rehearsal targets after migrations have rebuilt the schema. Do not restore a dump into live as a routine release action.

## Pre-deployment checkpoint

Before a live migration or first live deploy:

1. Confirm the target project reference in `LIVE_SUPABASE_PROJECT_REF`.
2. Confirm `SUPABASE_LIVE_DB_URL` belongs to that exact project reference.
3. Record the current build, migration version, release state, and UTC checkpoint time in the release evidence.
4. Inventory the Storage source files separately: object path, checksum when available, size, and retention status. Package 00C contains no source files, so this checkpoint is expected to be empty.
5. Create a logical backup outside the repository:

   ```powershell
   $env:LIVE_SUPABASE_PROJECT_REF = '<live-project-ref>'
   $env:SUPABASE_LIVE_DB_URL = '<live-db-connection-url>'
   npm run backup:logical -- --environment live --confirm-live-backup --output C:\secure-backups\dealer-operations-<timestamp>.sql
   ```

   On Windows, the backup script now invokes `npx` through `cmd.exe /c` so the `supabase db dump` call is executed reliably and any spawn failure is printed with the exit status.

`SUPABASE_LIVE_DB_URL` is a secret and must never be committed, pasted into issue text, or placed in frontend variables.

## Local restore rehearsal

Run the rehearsal after the dump is created and before calling the release recoverable. Docker and local Supabase must be running.

```powershell
npm run restore:rehearsal -- --environment local --input C:\secure-backups\dealer-operations-<timestamp>.sql
```

The script resets local Supabase, restores only into its database container, and proves that the Package 00 identity table exists. Record the command exit status and timestamp. If it fails, do not migrate or deploy live; repair the dump/procedure and repeat the rehearsal.

## Rollback versus data recovery

- **Code rollback:** deploy the previously known-good static build. It never deletes database records or Storage source files.
- **Schema issue:** use a version-controlled forward-fix migration. Do not perform an undocumented manual production edit.
- **Business-data recovery:** stop publication/mutation, preserve the current evidence, and use a reviewed logical-restore plan. This requires explicit incident approval; it is not a routine deploy rollback.

## Release evidence

For every live release retain: target project ref, backup filename/checkpoint time, Storage inventory result, local restore rehearsal result, build version, DB migration version, deploy URL, and package state. Keep backup files in access-controlled storage outside Git.
