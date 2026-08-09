import test from 'node:test';
import assert from 'node:assert/strict';
import { buildWindowsCommandLine, quoteCmdArg } from './backup-logical-helpers.mjs';

test('quoteCmdArg leaves simple values unquoted', () => {
  assert.equal(quoteCmdArg('supabase'), 'supabase');
});

test('quoteCmdArg quotes spaced values without injecting literal double quotes into plain args', () => {
  assert.equal(quoteCmdArg('C:\\secure backups\\dealer-operations.sql'), '"C:\\secure backups\\dealer-operations.sql"');
});

test('buildWindowsCommandLine does not wrap plain args in literal quotes', () => {
  assert.equal(
    buildWindowsCommandLine('npx', ['supabase', 'db', 'dump']),
    'npx supabase db dump',
  );
});
