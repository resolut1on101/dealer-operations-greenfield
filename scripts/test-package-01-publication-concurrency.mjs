import { execFileSync, spawn, spawnSync } from 'node:child_process'
import { resolveDockerCommand } from './docker-cli.mjs'

const projectRef = 'dealer-operations-greenfield'
const adminId = '50000000-0000-0000-0000-000000000001'
const docker = resolveDockerCommand()

const list = execFileSync(docker, ['ps', '--filter', `label=com.supabase.cli.project=${projectRef}`, '--format', '{{.ID}} {{.Names}}'], { encoding: 'utf8' })
const containerId = list.trim().split(/\r?\n/).find((line) => line.includes(`supabase_db_${projectRef}`))?.split(/\s+/)[0]
if (!containerId) throw new Error('Local Supabase database container is not running. Run `npm run supabase -- start` first.')

function psql(sql) {
  const result = spawnSync(docker, ['exec', '-i', containerId, 'psql', '-U', 'postgres', '-d', 'postgres', '-Atq', '-v', 'ON_ERROR_STOP=1'], { input: sql, encoding: 'utf8' })
  if (result.status !== 0) throw new Error(result.stderr)
  return result.stdout.trim()
}

function asAdmin(sql) {
  return psql(`begin; set local role authenticated; set local request.jwt.claim.role = 'authenticated'; set local request.jwt.claim.sub = '${adminId}'; ${sql}; commit;`)
}

function asService(sql) {
  return psql(`begin; set local role service_role; set local request.jwt.claim.role = 'service_role'; ${sql}; commit;`)
}

function session(sql) {
  const child = spawn(docker, ['exec', '-i', containerId, 'psql', '-U', 'postgres', '-d', 'postgres', '-Atq', '-v', 'ON_ERROR_STOP=1'], { stdio: ['pipe', 'pipe', 'pipe'] })
  child.stdin.end(sql)
  return new Promise((resolve) => {
    let stdout = ''; let stderr = ''
    child.stdout.on('data', (chunk) => { stdout += chunk })
    child.stderr.on('data', (chunk) => { stderr += chunk })
    child.on('close', (code) => resolve({ code, stdout, stderr }))
  })
}

const delay = (milliseconds) => new Promise((resolve) => setTimeout(resolve, milliseconds))

function cleanup() {
  psql(`delete from public.publication_heads where source_kind = 'SYNTHETIC_CONCURRENT';
    update public.import_batches set published_publication_id = null where created_by = '${adminId}';
    delete from public.publications where source_kind = 'SYNTHETIC_CONCURRENT';
    delete from public.import_batches where created_by = '${adminId}';
    delete from public.source_contract_versions where created_by = '${adminId}';
    delete from auth.users where id = '${adminId}';`)
}

async function createCandidate(contractId, fileHash, amount) {
  const batchId = asAdmin(`select (public.create_import_batch('${contractId}', 'concurrent-scope', 'Data', '["id","amount"]'::jsonb, '${fileHash}', 1, 1, 1, '{"amount":${amount}}'::jsonb)).id`)
  asService(`select public.verify_import_source_hash('${batchId}', '${fileHash}', 1)`)
  asAdmin(`select public.stage_import_chunk('${batchId}', 0, 0, public.import_chunk_payload_hash('[{"id":"${amount}","amount":"${amount}"}]'::jsonb), 1, '[{"id":"${amount}","amount":"${amount}"}]'::jsonb)`)
  asAdmin(`select public.validate_import_batch('${batchId}'); select public.reconcile_import_batch('${batchId}')`)
  return asAdmin(`select public.create_candidate_publication('${batchId}', '{"concurrency":${amount}}'::jsonb)`)
}

try {
  cleanup()
  psql(`
    insert into auth.users (id, instance_id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
    values ('${adminId}', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'package01-concurrency@example.test', 'not-used', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());
    update public.user_profiles set role = 'admin' where user_id = '${adminId}';`)
  const contractId = asAdmin(`select public.register_source_contract('SYNTHETIC_CONCURRENT', '1', 'Data', '["id","amount"]'::jsonb, '["id","amount"]'::jsonb, '{"amount":"amount"}'::jsonb, '{"amount":0}'::jsonb, 'FULL_REPLACE'::public.publication_mode)`)
  const firstCandidate = await createCandidate(contractId, 'a'.repeat(64), 10)
  const secondCandidate = await createCandidate(contractId, 'b'.repeat(64), 20)
  const first = session(`begin; set local role authenticated; set local request.jwt.claim.role = 'authenticated'; set local request.jwt.claim.sub = '${adminId}'; select pg_advisory_xact_lock(hashtextextended('package01:SYNTHETIC_CONCURRENT:concurrent-scope', 0)); select pg_sleep(1); select public.publish_candidate('${firstCandidate}', null); commit;`)
  await delay(200)
  const second = session(`begin; set local role authenticated; set local request.jwt.claim.role = 'authenticated'; set local request.jwt.claim.sub = '${adminId}'; select public.publish_candidate('${secondCandidate}', null); commit;`)
  const [firstResult, secondResult] = await Promise.all([first, second])
  if (firstResult.code !== 0 || !firstResult.stdout.includes('-')) throw new Error(`First publication failed: ${firstResult.stderr}`)
  if (secondResult.code === 0 || !secondResult.stderr.includes('Active publication changed')) throw new Error(`Concurrent stale publication was not rejected: ${secondResult.stderr}`)
  const active = psql(`select version from public.publication_heads where source_kind = 'SYNTHETIC_CONCURRENT' and scope_key = 'concurrent-scope'`)
  if (active !== '1') throw new Error(`Expected exactly one active publication, received version ${active}`)
  console.log('Package 01 concurrent publication PASS: one active version, stale concurrent publisher rejected.')
} finally {
  cleanup()
}
