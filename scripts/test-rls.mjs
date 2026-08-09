import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

const projectRef = 'dealer-operations-greenfield';
const list = spawnSync('docker', [
  'ps', '--filter', `label=com.supabase.cli.project=${projectRef}`, '--format', '{{.ID}} {{.Names}}',
], { encoding: 'utf8' });

if (list.status !== 0) {
  process.stderr.write(list.stderr);
  process.exit(list.status ?? 1);
}

const containerId = list.stdout
  .trim()
  .split(/\r?\n/)
  .find((line) => line.includes(`supabase_db_${projectRef}`))
  ?.split(/\s+/)[0];
if (!containerId) {
  throw new Error('Local Supabase database container is not running. Run `npm run supabase -- start` first.');
}

const sql = readFileSync(new URL('../supabase/tests/rls-foundation.sql', import.meta.url), 'utf8');
const result = spawnSync('docker', [
  'exec', '-i', containerId, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1',
], { input: sql, encoding: 'utf8' });

process.stdout.write(result.stdout);
process.stderr.write(result.stderr);
process.exit(result.status ?? 1);
