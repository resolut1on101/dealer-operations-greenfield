import { spawnSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import { resolveDockerCommand } from './docker-cli.mjs'

const projectRef = 'dealer-operations-greenfield'
const docker = resolveDockerCommand()
const list = spawnSync(docker, ['ps', '--filter', `label=com.supabase.cli.project=${projectRef}`, '--format', '{{.ID}} {{.Names}}'], { encoding: 'utf8' })
if (list.status !== 0) process.exit(list.status ?? 1)
const containerId = list.stdout.trim().split(/\r?\n/).find((line) => line.includes(`supabase_db_${projectRef}`))?.split(/\s+/)[0]
if (!containerId) throw new Error('Local Supabase database container is not running. Run `npm run supabase -- start` first.')
const result = spawnSync(docker, ['exec', '-i', containerId, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1'], {
  input: readFileSync(new URL('../supabase/tests/package-01-synthetic-load.sql', import.meta.url), 'utf8'), encoding: 'utf8',
})
process.stdout.write(result.stdout); process.stderr.write(result.stderr)
if (result.status !== 0) process.exit(result.status ?? 1)
console.log('Package 01 synthetic 2.5K/10K/25K/50K load PASS.')
