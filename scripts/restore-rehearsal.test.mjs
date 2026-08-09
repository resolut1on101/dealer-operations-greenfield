import test from 'node:test';
import assert from 'node:assert/strict';
import { buildWindowsCommandLine } from './backup-logical-helpers.mjs';

test('restore reset command uses safe Windows quoting', () => {
  assert.equal(
    buildWindowsCommandLine('npx', ['supabase', 'db', 'reset', '--local']),
    'npx supabase db reset --local',
  );
});

