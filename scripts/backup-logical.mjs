import { mkdirSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

function argument(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

if (argument('--environment') !== 'live' || !process.argv.includes('--confirm-live-backup')) {
  throw new Error('Refusing backup. Use --environment live --confirm-live-backup with an explicit output path.');
}

const output = argument('--output');
const projectRef = process.env.LIVE_SUPABASE_PROJECT_REF;
const databaseUrl = process.env.SUPABASE_LIVE_DB_URL;
if (!output || !output.endsWith('.sql') || !projectRef || !databaseUrl) {
  throw new Error('Required: --output <checkpoint.sql>, LIVE_SUPABASE_PROJECT_REF, and SUPABASE_LIVE_DB_URL.');
}
if (!databaseUrl.includes(projectRef)) {
  throw new Error('SUPABASE_LIVE_DB_URL does not identify LIVE_SUPABASE_PROJECT_REF; refusing the backup target.');
}

const outputPath = resolve(output);
mkdirSync(dirname(outputPath), { recursive: true });
// Schema recovery is version-controlled through migrations. The checkpoint is
// data-only so it restores cleanly after `supabase db reset --local`.
const npx = process.platform === 'win32' ? 'npx.cmd' : 'npx';
const result = spawnSync(npx, ['supabase', 'db', 'dump', '--db-url', databaseUrl, '--schema', 'public', '--data-only', '--file', outputPath], {
  stdio: 'inherit',
});
if (result.status !== 0) process.exit(result.status ?? 1);
console.log(`Logical backup completed: ${outputPath}`);
