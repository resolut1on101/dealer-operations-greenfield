import { randomUUID } from 'node:crypto'
import { spawn, spawnSync } from 'node:child_process'
import { resolveDockerCommand } from './docker-cli.mjs'

const projectRef = 'dealer-operations-greenfield'
const docker = resolveDockerCommand()
const list = spawnSync(docker, ['ps', '--filter', `label=com.supabase.cli.project=${projectRef}`, '--format', '{{.ID}} {{.Names}}'], { encoding: 'utf8' })
if (list.status !== 0) { if (list.stderr) process.stderr.write(list.stderr); process.exit(list.status ?? 1) }
const containerId = list.stdout.trim().split(/\r?\n/).find((line) => line.includes(`supabase_db_${projectRef}`))?.split(/\s+/)[0]
if (!containerId) throw new Error('Local Supabase database container is not running. Run `npm run supabase -- start` first.')

const adminId = randomUUID()
const scope = `P03-CONCURRENCY-${Date.now()}`

function execSyncSql(sql) {
  const result = spawnSync(docker, ['exec', '-i', containerId, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-At'], { input: sql, encoding: 'utf8' })
  if (result.stdout) process.stdout.write(result.stdout)
  if (result.stderr) process.stderr.write(result.stderr)
  if (result.status !== 0) process.exit(result.status ?? 1)
  return result.stdout.trim()
}

function spawnSql(sql) {
  const startedAt = Date.now()
  const child = spawn(docker, ['exec', '-i', containerId, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-At'], { stdio: ['pipe', 'pipe', 'pipe'] })
  let stdout = ''
  let stderr = ''
  child.stdout.setEncoding('utf8')
  child.stderr.setEncoding('utf8')
  child.stdout.on('data', (chunk) => { stdout += chunk })
  child.stderr.on('data', (chunk) => { stderr += chunk })
  child.stdin.end(sql)
  return new Promise((resolve, reject) => {
    child.on('error', reject)
    child.on('close', (code) => resolve({ code, stdout, stderr, elapsedMs: Date.now() - startedAt }))
  })
}

const authSql = `
set local role authenticated;
select set_config('request.jwt.claim.role','authenticated',true);
select set_config('request.jwt.claim.sub','${adminId}',true);
`

try {
  execSyncSql(`
    insert into auth.users(id,instance_id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
    values ('${adminId}','00000000-0000-0000-0000-000000000000','authenticated','authenticated','p03-concurrency-${adminId}@example.test','x',now(),'{}','{}',now(),now());
    update public.user_profiles set role='admin' where user_id='${adminId}';
  `)

  const sql1 = `
    begin;
    ${authSql}
    select pg_advisory_xact_lock(hashtextextended('product-domain:${scope}',0));
    select pg_sleep(1.25);
    select public.reconcile_product_domain_freshness('${scope}');
    commit;
  `
  const sql2 = `
    begin;
    ${authSql}
    select public.reconcile_product_domain_freshness('${scope}');
    commit;
  `

  // Real overlap: unlike the old spawnSync/spawnSync test, both psql processes are alive together.
  const first = spawnSql(sql1)
  await new Promise((resolve) => setTimeout(resolve, 200))
  const second = spawnSql(sql2)
  const [p1, p2] = await Promise.all([first, second])

  if (p1.stdout) process.stdout.write(p1.stdout)
  if (p1.stderr) process.stderr.write(p1.stderr)
  if (p2.stdout) process.stdout.write(p2.stdout)
  if (p2.stderr) process.stderr.write(p2.stderr)
  if (p1.code !== 0 || p2.code !== 0) throw new Error(`Concurrent reconciliation failed (session1=${p1.code}, session2=${p2.code})`)

  // Session 2 starts ~200 ms into a 1.25 s hold; threshold is conservative for CI variance.
  if (p2.elapsedMs < 850) throw new Error(`Concurrency serialization was not proven: contender completed in ${p2.elapsedMs} ms`)

  const finalState = execSyncSql(`select freshness_state from public.product_domain_heads where scope_key='${scope}';`)
  if (finalState !== 'PENDING_SOURCES') throw new Error(`Unexpected freshness state after concurrent reconcile: ${finalState || '<missing>'}`)

  console.log(`Package 03 concurrency serialization PASS. contender_wait_ms=${p2.elapsedMs}`)
} finally {
  execSyncSql(`
    delete from public.product_domain_heads where scope_key='${scope}';
    delete from auth.users where id='${adminId}';
  `)
}
