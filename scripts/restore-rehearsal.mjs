import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
import { runCrossPlatform } from './backup-logical-helpers.mjs';
import { resolveDockerCommand } from './docker-cli.mjs';

function argument(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

const input = argument('--input');
if (!input || argument('--environment') !== 'local') {
  throw new Error('Refusing restore. Use --environment local --input <logical-backup.sql>.');
}
const inputPath = resolve(input);
if (!existsSync(inputPath)) throw new Error(`Backup file not found: ${inputPath}`);

const resetInvocation = runCrossPlatform('npx', ['supabase', 'db', 'reset', '--local'], { encoding: 'utf8' });
const reset = spawnSync(resetInvocation.command, resetInvocation.args, resetInvocation.options);
if (reset.stdout) process.stdout.write(reset.stdout);
if (reset.stderr) process.stderr.write(reset.stderr);
if (reset.error) {
  console.error('Local restore reset failed with a spawn error:');
  console.error(reset.error);
}
if (reset.status !== 0) {
  console.error(`Local restore reset exited with status ${reset.status ?? 'unknown'}.`);
  process.exit(reset.status ?? 1);
}

const projectRef = 'dealer-operations-greenfield';
const docker = resolveDockerCommand();
const containers = spawnSync(docker, ['ps', '--filter', `label=com.supabase.cli.project=${projectRef}`, '--format', '{{.ID}} {{.Names}}'], { encoding: 'utf8' });
if (containers.status !== 0) throw new Error(containers.stderr || 'Could not inspect the local Supabase database container.');
const containerId = containers.stdout.trim().split(/\r?\n/).find((line) => line.includes(`supabase_db_${projectRef}`))?.split(/\s+/)[0];
if (!containerId) throw new Error('Local Supabase database container is not running.');

const restore = spawnSync(docker, ['exec', '-i', containerId, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], {
  input: readFileSync(inputPath),
  encoding: 'utf8',
});
process.stdout.write(restore.stdout);
process.stderr.write(restore.stderr);
if (restore.error) {
  console.error('Local restore replay failed with a spawn error:');
  console.error(restore.error);
}
if (restore.status !== 0) process.exit(restore.status ?? 1);

const check = spawnSync(docker, ['exec', containerId, 'psql', '-U', 'postgres', '-d', 'postgres', '-At', '-c', "select to_regclass('public.user_profiles') is not null"], { encoding: 'utf8' });
if (check.status !== 0 || check.stdout.trim() !== 't') throw new Error('Restore completed but the Package 00 identity table was not found.');
console.log(`Local restore rehearsal PASS: ${inputPath}`);
