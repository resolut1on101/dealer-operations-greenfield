import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { assertionSql, discoverPublicTables, shouldInjectP02uAssertions, transactionCommitSql } from './restore-rehearsal.mjs';
import { buildWindowsCommandLine } from './backup-logical-helpers.mjs';

test('restore reset command uses safe Windows quoting', () => {
  assert.equal(
    buildWindowsCommandLine('npx', ['supabase', 'db', 'reset', '--local']),
    'npx supabase db reset --local',
  );
});

test('restore assertions enforce the canonical customer ID scope', () => {
  const sql = assertionSql();
  assert.match(sql, /count\(\*\) FILTER \(WHERE customer_id IS NULL OR customer_id !~ '\^500\[0-9\]\+\$'\)/u);
  assert.doesNotMatch(sql, /count\(\*\) FILTER \(WHERE raw_status/u);
  assert.match(sql, /observation_count <> 3559/u);
  assert.match(sql, /resolved_customers <> 1781/u);
  assert.match(sql, /active_customers <> 1781/u);
  assert.match(sql, /non_500 <> 0/u);
});

test('P02U assertions are explicit opt-in and independent from failure proof', () => {
  assert.equal(shouldInjectP02uAssertions(['node', 'restore-rehearsal.mjs']), false);
  assert.equal(shouldInjectP02uAssertions(['node', 'restore-rehearsal.mjs', '--verify-p02u-accepted-baseline']), true);
  assert.equal(shouldInjectP02uAssertions(['node', 'restore-rehearsal.mjs', '--failure-proof']), false);
  assert.equal(shouldInjectP02uAssertions(['node', 'restore-rehearsal.mjs', '--failure-proof', '--verify-p02u-accepted-baseline']), false);
});

test('generic replay omits P02U assertions and flagged replay checks before COMMIT', () => {
  const generic = transactionCommitSql(false);
  const flagged = transactionCommitSql(true);
  assert.doesNotMatch(generic, /P02 aggregate identity assertion/u);
  assert.match(flagged, /P02 aggregate identity assertion/u);
  assert.ok(flagged.indexOf('P02 aggregate identity assertion') < flagged.indexOf('COMMIT;'));
});

test('restore discovers quoted INSERT and COPY public tables without reading rows', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'restore-rehearsal-'));
  const file = join(directory, 'fixture.sql');
  await writeFile(file, [
    'INSERT INTO "public"."source_contract_versions" ("id") VALUES',
    '  (\'not inspected\');',
    'COPY public.import_chunks (id) FROM stdin;',
    '\\.',
  ].join('\n'));
  try {
    assert.deepEqual(await discoverPublicTables(file), ['import_chunks', 'source_contract_versions']);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('restore rejects non-public data statements', async () => {
  const directory = await mkdtemp(join(tmpdir(), 'restore-rehearsal-'));
  const file = join(directory, 'fixture.sql');
  await writeFile(file, 'INSERT INTO auth.users (id) VALUES (\'not inspected\');\n');
  try {
    await assert.rejects(discoverPublicTables(file), /Unsupported logical dump data statement shape/);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});
