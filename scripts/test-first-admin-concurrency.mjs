import { execFileSync, spawn, spawnSync } from 'node:child_process';
import { resolveDockerCommand } from './docker-cli.mjs';

const projectRef = 'dealer-operations-greenfield';
const firstTargetId = '20000000-0000-0000-0000-000000000001';
const secondTargetId = '20000000-0000-0000-0000-000000000002';
const docker = resolveDockerCommand();

function findDatabaseContainer() {
  const list = execFileSync(docker, [
    'ps', '--filter', `label=com.supabase.cli.project=${projectRef}`, '--format', '{{.ID}} {{.Names}}',
  ], { encoding: 'utf8' });
  const containerId = list.trim().split(/\r?\n/)
    .find((line) => line.includes(`supabase_db_${projectRef}`))?.split(/\s+/)[0];
  if (!containerId) throw new Error('Local Supabase database container is not running.');
  return containerId;
}

function psql(containerId, sql) {
  const result = spawnSync(docker, [
    'exec', '-i', containerId, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-At',
  ], { input: sql, encoding: 'utf8' });
  if (result.status !== 0) throw new Error(result.stderr || 'psql command failed');
  return result.stdout.trim();
}

function psqlSession(containerId, sql) {
  const child = spawn(docker, [
    'exec', '-i', containerId, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-At',
  ], { stdio: ['pipe', 'pipe', 'pipe'] });
  child.stdin.end(sql);
  return new Promise((resolve, reject) => {
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', (chunk) => { stdout += chunk; });
    child.stderr.on('data', (chunk) => { stderr += chunk; });
    child.on('error', reject);
    child.on('close', (code) => resolve({ code, stdout, stderr }));
  });
}

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds));
const containerId = findDatabaseContainer();
const cleanupSql = `delete from auth.users where id in ('${firstTargetId}', '${secondTargetId}');`;

try {
  psql(containerId, `
    delete from auth.users where id in ('${firstTargetId}', '${secondTargetId}');
    insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at) values
      ('${firstTargetId}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'concurrency-a@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
      ('${secondTargetId}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'concurrency-b@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());
  `);

  const firstSession = psqlSession(containerId, `
    begin;
    set local role service_role;
    set local request.jwt.claim.role = 'service_role';
    select pg_advisory_xact_lock(hashtextextended('public.bootstrap_first_admin', 0));
    select pg_sleep(1);
    select public.bootstrap_first_admin('${firstTargetId}');
    select pg_sleep(1);
    commit;
  `);

  await delay(250);
  const secondSession = psqlSession(containerId, `
    begin;
    set local role service_role;
    set local request.jwt.claim.role = 'service_role';
    select public.bootstrap_first_admin('${secondTargetId}');
    commit;
  `);
  const [firstResult, secondResult] = await Promise.all([firstSession, secondSession]);
  if (firstResult.code !== 0 || !firstResult.stdout.includes('admin')) {
    throw new Error(`First concurrent bootstrap did not succeed: ${firstResult.stderr}`);
  }
  if (secondResult.code === 0 || !secondResult.stderr.includes('An admin already exists')) {
    throw new Error(`Second concurrent bootstrap was not rejected after serialization: ${secondResult.stderr}`);
  }

  const roles = psql(containerId, `
    select user_id || ':' || role::text from public.user_profiles
    where user_id in ('${firstTargetId}', '${secondTargetId}') order by user_id;
  `);
  const expected = `${firstTargetId}:admin\n${secondTargetId}:viewer`;
  if (roles !== expected) throw new Error(`Concurrent bootstrap assigned unexpected roles: ${roles}`);
  console.log('Concurrent first-admin bootstrap PASS: two independent DB sessions produced one admin and one rejected call.');
} finally {
  psql(containerId, cleanupSql);
}
