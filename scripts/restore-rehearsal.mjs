import { createReadStream, existsSync } from 'node:fs';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import { basename, resolve } from 'node:path';
import { spawn, spawnSync } from 'node:child_process';
import { createInterface } from 'node:readline';
import { runCrossPlatform } from './backup-logical-helpers.mjs';
import { resolveDockerCommand } from './docker-cli.mjs';

const projectRef = 'dealer-operations-greenfield';
const localEnvironment = 'local';

function argument(name) {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

function hasArgument(name) {
  return process.argv.includes(name);
}

export function shouldInjectP02uAssertions(args) {
  return args.includes('--verify-p02u-accepted-baseline') && !args.includes('--failure-proof');
}

export function quoteIdentifier(identifier) {
  return `"${String(identifier).replaceAll('"', '""')}"`;
}

function quoteLiteral(value) {
  return `'${String(value).replaceAll("'", "''")}'`;
}

function parseDumpRelation(line) {
  const match = line.match(
    /^\s*(?:INSERT\s+INTO|COPY)\s+(?:"((?:[^"]|"")*)"|([A-Za-z_][A-Za-z0-9_$]*))\.(?:"((?:[^"]|"")*)"|([A-Za-z_][A-Za-z0-9_$]*))(?:\s|\(|;|$)/u,
  );
  if (!match) return undefined;
  const schema = (match[1] ?? match[2]).replaceAll('""', '"');
  const table = (match[3] ?? match[4]).replaceAll('""', '"');
  return { schema, table };
}

export async function discoverPublicTables(inputPath) {
  const tables = new Set();
  const input = createReadStream(inputPath, { encoding: 'utf8' });
  const lines = createInterface({ input, crlfDelay: Infinity });
  try {
    for await (const line of lines) {
      if (!/^\s*(?:INSERT\s+INTO|COPY)\s+/u.test(line)) continue;
      const relation = parseDumpRelation(line);
      if (!relation || relation.schema !== 'public' || relation.table.length === 0) {
        throw new Error(`Unsupported logical dump data statement shape near line ${line.slice(0, 80)}`);
      }
      tables.add(relation.table);
    }
  } finally {
    input.destroy();
  }
  if (tables.size === 0) throw new Error('Logical dump contains no supported public data tables.');
  return [...tables].sort();
}

function runPsql(docker, containerId, args, options = {}) {
  return spawnSync(docker, ['exec', '-i', containerId, 'psql', '-U', 'postgres', '-d', 'postgres', ...args], {
    encoding: 'utf8',
    ...options,
  });
}

function localDatabaseContainer(docker) {
  const containers = spawnSync(
    docker,
    ['ps', '--filter', `label=com.supabase.cli.project=${projectRef}`, '--format', '{{.ID}} {{.Names}}'],
    { encoding: 'utf8' },
  );
  if (containers.status !== 0) throw new Error(containers.stderr || 'Could not inspect the local Supabase database container.');
  const line = containers.stdout.trim().split(/\r?\n/).find((value) => value.includes(`supabase_db_${projectRef}`));
  const containerId = line?.split(/\s+/)[0];
  if (!containerId) throw new Error('Local Supabase database container is not running.');

  const inspect = spawnSync(docker, ['inspect', '--format', '{{index .Config.Labels "com.supabase.cli.project"}}', containerId], { encoding: 'utf8' });
  if (inspect.status !== 0 || inspect.stdout.trim() !== projectRef) throw new Error('Refusing restore: target is not the isolated local Supabase database.');
  return containerId;
}

function publicTableArraySql(tables) {
  return `ARRAY[${tables.map((table) => quoteLiteral(table)).join(', ')}]::text[]`;
}

function dependencyQuery(tables) {
  return `
SELECT child.relname || '|' || child_ns.nspname || '|' || parent.relname || '|' || parent_ns.nspname
FROM pg_constraint constraint_row
JOIN pg_class child ON child.oid = constraint_row.conrelid
JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
JOIN pg_class parent ON parent.oid = constraint_row.confrelid
JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
WHERE constraint_row.contype = 'f'
  AND ((child_ns.nspname = 'public' AND child.relname = ANY(${publicTableArraySql(tables)}))
    OR (parent_ns.nspname = 'public' AND parent.relname = ANY(${publicTableArraySql(tables)})))
ORDER BY 1;`;
}

function expandPublicForeignKeyClosure(docker, containerId, initialTables) {
  const result = new Set(initialTables);
  let changed = true;
  while (changed) {
    changed = false;
    const dependencies = runPsql(docker, containerId, ['-At', '-F', '|', '-c', dependencyQuery([...result])]);
    if (dependencies.status !== 0) throw new Error(dependencies.stderr || 'Could not inspect local public foreign keys.');
    for (const row of dependencies.stdout.trim().split(/\r?\n/).filter(Boolean)) {
      const [child, childSchema, parent, parentSchema] = row.split('|');
      if (childSchema !== 'public' && parentSchema === 'public' && result.has(parent)) {
        throw new Error(`Refusing restore: a non-public table references checkpoint public data (${childSchema}.${child} -> ${parentSchema}.${parent}).`);
      }
      if (childSchema === 'public' && !result.has(child) && result.has(parent)) {
        result.add(child);
        changed = true;
      }
      if (parentSchema === 'public' && !result.has(parent) && result.has(child)) {
        result.add(parent);
        changed = true;
      }
    }
  }
  return [...result].sort();
}

export function assertionSql() {
  return String.raw`
DO $restore_assertions$
DECLARE
  customer_versions integer;
  ticari_contracts integer;
  ticari_active integer;
  ticari_heads integer;
  ticari_publications integer;
  batch_status text;
  observation_count bigint;
  resolved_customers bigint;
  active_customers bigint;
  non_500 bigint;
BEGIN
  SELECT count(*) INTO customer_versions FROM public.source_contract_versions WHERE source_kind = 'CUSTOMER_MASTER' AND version IN ('2', '3', '4');
  IF customer_versions <> 3 THEN RAISE EXCEPTION 'CUSTOMER_MASTER version assertion failed'; END IF;
  IF EXISTS (SELECT 1 FROM public.source_contract_versions WHERE source_kind = 'CUSTOMER_MASTER' AND version IN ('2', '3') AND (is_active OR retired_at IS NULL)) THEN RAISE EXCEPTION 'CUSTOMER_MASTER retired-state assertion failed'; END IF;
  IF NOT EXISTS (SELECT 1 FROM public.source_contract_versions WHERE source_kind = 'CUSTOMER_MASTER' AND version = '4' AND is_active AND retired_at IS NULL) THEN RAISE EXCEPTION 'CUSTOMER_MASTER v4 active-state assertion failed'; END IF;
  SELECT count(*), count(*) FILTER (WHERE is_active) INTO ticari_contracts, ticari_active FROM public.source_contract_versions WHERE source_kind = 'TICARI_STOK';
  SELECT count(*) INTO ticari_heads FROM public.publication_heads WHERE source_kind = 'TICARI_STOK';
  SELECT count(*) INTO ticari_publications FROM public.publications WHERE source_kind = 'TICARI_STOK';
  IF ticari_contracts <> 1 OR ticari_active <> 1 OR ticari_heads <> 4 OR ticari_publications <> 4 THEN RAISE EXCEPTION 'TICARI_STOK fingerprint assertion failed'; END IF;
  SELECT status INTO batch_status FROM public.import_batches WHERE id = 'b7130543-a634-48ef-be87-62726e778f5a';
  IF batch_status <> 'PUBLISHED' THEN RAISE EXCEPTION 'P02 batch status assertion failed'; END IF;
  SELECT count(*) INTO observation_count FROM public.customer_master_observations WHERE snapshot_id = 'ba9d2638-21ee-4021-91ab-7fde5df8d501';
  SELECT count(DISTINCT customer_id) INTO resolved_customers FROM public.customer_resolutions WHERE snapshot_id = 'ba9d2638-21ee-4021-91ab-7fde5df8d501';
  SELECT count(DISTINCT customer_id) INTO active_customers FROM public.customers WHERE active_snapshot_id = 'ba9d2638-21ee-4021-91ab-7fde5df8d501';
  SELECT count(*) FILTER (WHERE customer_id IS NULL OR customer_id !~ '^500[0-9]+$') INTO non_500 FROM public.customer_master_observations WHERE snapshot_id = 'ba9d2638-21ee-4021-91ab-7fde5df8d501';
  IF observation_count <> 3559 OR resolved_customers <> 1781 OR active_customers <> 1781 OR non_500 <> 0 THEN RAISE EXCEPTION 'P02 aggregate identity assertion failed (observations=%, resolved=%, active=%, non_500=%)', observation_count, resolved_customers, active_customers, non_500; END IF;
END
$restore_assertions$;
`;
}

export function transactionCommitSql(assertions) {
  return `${assertions ? assertionSql() : ''}\nCOMMIT;\n`;
}

function transactionPrefix(tables) {
  const relationList = tables.map((table) => `public.${quoteIdentifier(table)}`).join(', ');
  return `BEGIN;\nTRUNCATE TABLE ${relationList} RESTART IDENTITY;\n`;
}

function replayTransaction(docker, containerId, inputPath, tables, { assertions = true } = {}) {
  return new Promise((resolvePromise, reject) => {
    const child = spawn(docker, ['exec', '-i', containerId, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], { stdio: ['pipe', 'pipe', 'pipe'] });
    let stderr = '';
    child.stdout.on('data', (chunk) => process.stdout.write(chunk));
    child.stderr.on('data', (chunk) => {
      stderr += chunk;
      process.stderr.write(chunk);
    });
    child.on('error', reject);
    child.on('close', (status) => status === 0 ? resolvePromise() : reject(new Error(`Transactional local restore exited with status ${status}: ${stderr.trim()}`)));
    child.stdin.write(transactionPrefix(tables));
    const dump = createReadStream(inputPath);
    dump.on('error', reject);
    dump.on('end', () => {
      child.stdin.end(transactionCommitSql(assertions));
    });
    dump.pipe(child.stdin, { end: false });
  });
}

async function failureRollbackProof(docker, containerId) {
  const before = runPsql(docker, containerId, ['-At', '-c', 'select count(*) from public.source_contract_versions']);
  if (before.status !== 0) throw new Error(before.stderr || 'Could not capture the local pre-replay aggregate for rollback proof.');
  const directory = await mkdtemp(`${tmpdir()}\\restore-rollback-`);
  const fixture = `${directory}\\failure.sql`;
  try {
    await writeFile(fixture, [
      'INSERT INTO "public"."source_contract_versions" (source_kind, version, required_sheet, required_headers, required_fields, control_total_fields, publication_mode, created_by)',
      "SELECT 'ROLLBACK_FIXTURE', '1', 'fixture', '[]'::jsonb, '[]'::jsonb, '{}'::jsonb, 'FULL_REPLACE'::public.publication_mode, id FROM auth.users LIMIT 1;",
      'SELECT 1 / 0;',
    ].join('\n'));
    const clearTables = expandPublicForeignKeyClosure(docker, containerId, ['source_contract_versions']);
    await assert.rejects(replayTransaction(docker, containerId, fixture, clearTables, { assertions: false }));
    const after = runPsql(docker, containerId, ['-At', '-c', 'select count(*) from public.source_contract_versions']);
    if (after.status !== 0 || after.stdout.trim() !== before.stdout.trim()) throw new Error('Rollback proof failed: local public data was not restored to its pre-replay aggregate.');
    console.log('Local transactional rollback proof PASS.');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}

async function main() {
  const input = argument('--input');
  if (!input || argument('--environment') !== localEnvironment) throw new Error('Refusing restore. Use --environment local --input <logical-backup.sql>.');
  const inputPath = resolve(input);
  if (!existsSync(inputPath)) throw new Error(`Backup file not found: ${inputPath}`);
  if (basename(inputPath).length === 0) throw new Error('Invalid checkpoint path.');

  const resetInvocation = runCrossPlatform('npx', ['supabase', 'db', 'reset', '--local'], { encoding: 'utf8' });
  const reset = spawnSync(resetInvocation.command, resetInvocation.args, resetInvocation.options);
  if (reset.stdout) process.stdout.write(reset.stdout);
  if (reset.stderr) process.stderr.write(reset.stderr);
  if (reset.error || reset.status !== 0) throw new Error(`Local restore reset failed with status ${reset.status ?? 'unknown'}.`);

  const docker = resolveDockerCommand();
  const containerId = localDatabaseContainer(docker);
  if (hasArgument('--failure-proof')) {
    await failureRollbackProof(docker, containerId);
    return;
  }
  const discoveredTables = await discoverPublicTables(inputPath);
  const clearTables = expandPublicForeignKeyClosure(docker, containerId, discoveredTables);
  console.log(`Local checkpoint metadata: ${discoveredTables.length} replay tables; ${clearTables.length} FK-safe clear tables.`);
  await replayTransaction(docker, containerId, inputPath, clearTables, {
    assertions: shouldInjectP02uAssertions(process.argv),
  });

  const check = runPsql(docker, containerId, ['-At', '-c', "select to_regclass('public.user_profiles') is not null"]);
  if (check.status !== 0 || check.stdout.trim() !== 't') throw new Error('Restore completed but the Package 00 identity table was not found.');
  console.log(`Local restore rehearsal PASS: ${inputPath}`);
}

if (process.argv[1] && resolve(fileURLToPath(import.meta.url)) === resolve(process.argv[1])) {
  main().catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exitCode = 1;
  });
}
