import { basename, dirname } from 'node:path'
import { createInterface } from 'node:readline/promises'
import { stdin as input, stdout as output } from 'node:process'
import { createClient } from '@supabase/supabase-js'

const LIVE_REF = 'ncwtlaiormtunpryxjmu'
const SOURCE_KIND = 'TICARI_STOK'
const SCOPE = process.env.PACKAGE01_LIVE_SCOPE ?? 'uat-package-01-ticari-stok-10k-interrupt-01'
const EXPECTED_ACTIVE_PUBLICATION = '7e029c85-976b-4358-a159-0f7f234d5689'
const UAT08_INVALID_BATCH = '6af9a271-59e4-4df1-b97f-13e1f3d4010a'
const url = process.env.PACKAGE01_LIVE_SUPABASE_URL
const key = process.env.PACKAGE01_LIVE_SUPABASE_PUBLISHABLE_KEY

function fail(message) { throw new Error(message) }
function liveProjectUrl(value) {
  try { return new URL(value).hostname === `${LIVE_REF}.supabase.co` } catch { return false }
}

if (!liveProjectUrl(url)) fail('LIVE guard: PACKAGE01_LIVE_SUPABASE_URL must target the approved LIVE project')
if (!key) fail('Missing PACKAGE01_LIVE_SUPABASE_PUBLISHABLE_KEY')

let email = process.env.PACKAGE01_LIVE_ADMIN_EMAIL
let password = process.env.PACKAGE01_LIVE_ADMIN_PASSWORD
if (!email || !password) {
  const prompt = createInterface({ input, output })
  email ??= await prompt.question('LIVE admin email: ')
  password ??= await prompt.question('LIVE admin password: ')
  prompt.close()
}
if (!email || !password) fail('LIVE admin credentials were not supplied')

const client = createClient(url, key)
const auth = await client.auth.signInWithPassword({ email, password })
if (auth.error || !auth.data.user) fail(`Admin sign-in failed: ${auth.error?.message ?? 'unknown error'}`)

try {
  const batchesResult = await client.from('import_batches')
    .select('id, status, storage_bucket, storage_object_path, expected_rows, staged_rows, expected_chunks, received_chunks, published_publication_id')
    .eq('source_kind', SOURCE_KIND).eq('scope_key', SCOPE).order('created_at')
  if (batchesResult.error) fail(`import_batches read failed: ${batchesResult.error.message}`)
  const batches = batchesResult.data ?? []

  const perBatch = []
  const storageObjects = []
  for (const batch of batches) {
    const [chunks, staging, objects] = await Promise.all([
      client.from('import_chunks').select('id', { count: 'exact', head: true }).eq('batch_id', batch.id),
      client.from('staging_rows').select('id', { count: 'exact', head: true }).eq('batch_id', batch.id),
      client.storage.from(batch.storage_bucket).list(dirname(batch.storage_object_path), { limit: 100 }),
    ])
    if (chunks.error || staging.error || objects.error) fail(`batch ${batch.id} evidence read failed: ${chunks.error?.message ?? staging.error?.message ?? objects.error?.message}`)
    const entries = objects.data ?? []
    const expectedObject = basename(batch.storage_object_path)
    const extras = entries.filter((entry) => entry.name !== expectedObject).map((entry) => entry.name)
    for (const entry of entries) storageObjects.push({ batch_id: batch.id, name: entry.name, bytes: Number(entry.metadata?.size ?? 0) })
    perBatch.push({
      batch_id: batch.id,
      status: batch.status,
      expected_chunks: batch.expected_chunks,
      chunks: chunks.count ?? 0,
      expected_staging_rows: batch.expected_rows,
      staging_rows: staging.count ?? 0,
      storage_objects: entries.length,
      storage_extra_objects: extras,
      published_publication_id: batch.published_publication_id,
    })
  }

  const [publications, heads, invalidBatch] = await Promise.all([
    client.from('publications').select('id', { count: 'exact', head: true }).eq('source_kind', SOURCE_KIND).eq('scope_key', SCOPE),
    client.from('publication_heads').select('active_publication_id, version').eq('source_kind', SOURCE_KIND).eq('scope_key', SCOPE),
    client.from('import_batches').select('id, status, published_publication_id').eq('id', UAT08_INVALID_BATCH).maybeSingle(),
  ])
  if (publications.error || heads.error || invalidBatch.error) fail(`publication evidence read failed: ${publications.error?.message ?? heads.error?.message ?? invalidBatch.error?.message}`)

  const mismatchedBatches = perBatch.filter((batch) => batch.chunks !== batch.expected_chunks || batch.staging_rows !== batch.expected_staging_rows)
  const extraStorageObjects = perBatch.flatMap((batch) => batch.storage_extra_objects.map((name) => ({ batch_id: batch.batch_id, name })))
  const failedOrBlockedBatches = perBatch.filter((batch) => ['FAILED', 'BLOCKED'].includes(batch.status)).length
  const activePublicationCount = (heads.data ?? []).filter((head) => head.active_publication_id).length
  const invalidBatchPublicationCreated = Boolean(invalidBatch.data?.published_publication_id)
  const passed = heads.data?.length === 1
    && heads.data[0].active_publication_id === EXPECTED_ACTIVE_PUBLICATION
    && publications.count === 1
    && activePublicationCount === 1
    && !invalidBatchPublicationCreated
    && mismatchedBatches.length === 0
    && extraStorageObjects.length === 0

  console.log(JSON.stringify({
    result: passed ? 'PASS' : 'FAIL',
    uat: 'UAT-09',
    scope: SCOPE,
    storage: {
      object_count: storageObjects.length,
      total_bytes: storageObjects.reduce((total, object) => total + object.bytes, 0),
      objects_by_batch: storageObjects,
      duplicate_or_orphan_observation: extraStorageObjects.length ? extraStorageObjects : 'none in inspected batch directories',
    },
    database: {
      batch_count: batches.length,
      chunk_count: perBatch.reduce((total, batch) => total + batch.chunks, 0),
      staging_row_count: perBatch.reduce((total, batch) => total + batch.staging_rows, 0),
      publication_count: publications.count ?? 0,
      active_publication_count: activePublicationCount,
      failed_or_blocked_batch_count: failedOrBlockedBatches,
      batches: perBatch,
    },
    uat_08_failed_batch: {
      batch_id: UAT08_INVALID_BATCH,
      status: invalidBatch.data?.status ?? null,
      publication_created: invalidBatchPublicationCreated,
    },
    active_publication: heads.data?.[0]?.active_publication_id ?? null,
    egress_evidence: 'NOT MEASURABLE FROM AVAILABLE EVIDENCE (no reliable historical Supabase egress metric is exposed through this read-only admin-auth path; this alone is not a Package 01 failure)',
    resource_usage_conclusion: passed ? 'No duplicate/orphan artifacts or runaway growth detected in the inspected UAT scope.' : 'Investigate the failed evidence checks before accepting Package 01.',
  }, null, 2))
  process.exitCode = passed ? 0 : 1
} finally {
  await client.auth.signOut()
}
