import { createHash } from 'node:crypto'
import { deflateRawSync, inflateRawSync } from 'node:zlib'
import { mkdirSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs'
import { basename, dirname, resolve } from 'node:path'
import { createInterface } from 'node:readline/promises'
import { stdin as input, stdout as output } from 'node:process'
import { createClient } from '@supabase/supabase-js'

const LIVE_REF = 'ncwtlaiormtunpryxjmu'
const DEFAULT_FILE = 'C:/Users/monds/Desktop/YENI/VERI_REFERANS/02_BUYUK_YUK_TESTLERI/TICARI_STOK_LOAD_10K.xlsx'
const MANIFEST = 'C:/Users/monds/Desktop/YENI/VERI_REFERANS/04_KONTROL_TOPLAMLARI/CONTROL_MANIFEST.json'
const CHUNK_SIZE = 1000
const args = new Set(process.argv.slice(2))
const fileArg = process.argv.find((value) => value.startsWith('--file='))?.slice(7) ?? DEFAULT_FILE
const interruptAfter = Number(process.argv.find((value) => value.startsWith('--interrupt-after='))?.slice(18) ?? '')
const resumeBatchId = process.argv.find((value) => value.startsWith('--resume-batch='))?.slice(15)
const invalidRequiredField = process.argv.find((value) => value.startsWith('--uat-08-invalid-required-field='))?.slice(32)
const isDryRun = args.has('--dry-run')
const configuredUrl = process.env.PACKAGE01_LIVE_SUPABASE_URL
let isLive = false
try { isLive = new URL(configuredUrl).hostname === `${LIVE_REF}.supabase.co` } catch { isLive = false }

function usage() {
  console.log('Usage: node scripts/package-01-live-uat-runner.mjs --dry-run [--file=path]')
  console.log('Interrupt: --confirm-live --interrupt-after=3; resume: --confirm-live --resume-batch=<batch_id>')
  console.log('UAT-08: --confirm-live --uat-08-invalid-required-field=<required_header> (creates and removes a temporary invalid XLSX copy)')
  console.log('LIVE: set PACKAGE01_LIVE_SUPABASE_URL, PACKAGE01_LIVE_SUPABASE_PUBLISHABLE_KEY, PACKAGE01_LIVE_ADMIN_EMAIL, PACKAGE01_LIVE_ADMIN_PASSWORD and add --confirm-live.')
}

function xmlDecode(value) {
  return value.replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&#(\d+);/g, (_, code) => String.fromCodePoint(Number(code)))
}

function zipEntries(buffer) {
  const entries = new Map()
  let offset = buffer.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]))
  if (offset < 0) throw new Error('Invalid XLSX: end of central directory not found')
  const count = buffer.readUInt16LE(offset + 10)
  const centralOffset = buffer.readUInt32LE(offset + 16)
  offset = centralOffset
  for (let index = 0; index < count; index += 1) {
    if (buffer.readUInt32LE(offset) !== 0x02014b50) throw new Error('Invalid XLSX central directory')
    const method = buffer.readUInt16LE(offset + 10)
    const compressed = buffer.readUInt32LE(offset + 20)
    const nameLength = buffer.readUInt16LE(offset + 28)
    const extraLength = buffer.readUInt16LE(offset + 30)
    const commentLength = buffer.readUInt16LE(offset + 32)
    const localOffset = buffer.readUInt32LE(offset + 42)
    const name = buffer.subarray(offset + 46, offset + 46 + nameLength).toString('utf8')
    const localNameLength = buffer.readUInt16LE(localOffset + 26)
    const localExtraLength = buffer.readUInt16LE(localOffset + 28)
    const start = localOffset + 30 + localNameLength + localExtraLength
    const body = buffer.subarray(start, start + compressed)
    entries.set(name, method === 8 ? inflateRawSync(body) : body)
    offset += 46 + nameLength + extraLength + commentLength
  }
  return entries
}

function crc32(buffer) {
  let crc = 0xffffffff
  for (const byte of buffer) {
    crc ^= byte
    for (let bit = 0; bit < 8; bit += 1) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1))
  }
  return (crc ^ 0xffffffff) >>> 0
}

function zipXlsx(entries) {
  const chunks = []
  const central = []
  let offset = 0
  for (const [name, body] of entries) {
    const nameBytes = Buffer.from(name)
    const compressed = deflateRawSync(body)
    const crc = crc32(body)
    const local = Buffer.alloc(30)
    local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(0, 6); local.writeUInt16LE(8, 8)
    local.writeUInt32LE(crc, 14); local.writeUInt32LE(compressed.length, 18); local.writeUInt32LE(body.length, 22)
    local.writeUInt16LE(nameBytes.length, 26); local.writeUInt16LE(0, 28)
    chunks.push(local, nameBytes, compressed)
    const header = Buffer.alloc(46)
    header.writeUInt32LE(0x02014b50, 0); header.writeUInt16LE(20, 4); header.writeUInt16LE(20, 6); header.writeUInt16LE(0, 8); header.writeUInt16LE(8, 10)
    header.writeUInt32LE(crc, 16); header.writeUInt32LE(compressed.length, 20); header.writeUInt32LE(body.length, 24)
    header.writeUInt16LE(nameBytes.length, 28); header.writeUInt32LE(offset, 42)
    central.push(header, nameBytes)
    offset += local.length + nameBytes.length + compressed.length
  }
  const centralBytes = Buffer.concat(central)
  const end = Buffer.alloc(22)
  end.writeUInt32LE(0x06054b50, 0); end.writeUInt16LE(entries.size, 8); end.writeUInt16LE(entries.size, 10)
  end.writeUInt32LE(centralBytes.length, 12); end.writeUInt32LE(offset, 16)
  return Buffer.concat([...chunks, centralBytes, end])
}

function columnLetters(index) { let result = ''; for (let value = index; value >= 0; value = Math.floor(value / 26) - 1) result = String.fromCharCode((value % 26) + 65) + result; return result }

function createInvalidRequiredFieldFixture(originalBytes, headers, field) {
  const fieldIndex = headers.indexOf(field)
  if (fieldIndex < 0) fail(`UAT-08 field is not a source header: ${field}`)
  const entries = zipEntries(originalBytes)
  const worksheetName = 'xl/worksheets/sheet1.xml'
  const worksheet = entries.get(worksheetName)?.toString('utf8')
  if (!worksheet) fail('UAT-08 fixture could not find first worksheet')
  const target = `${columnLetters(fieldIndex)}2`
  const mutated = worksheet.replace(/<row\b[^>]*r="2"[^>]*>([\s\S]*?)<\/row>/, (row) => row.replace(new RegExp(`<c\\s+[^>]*\\br="${target}"[^>]*>[\\s\\S]*?<\\/c>`), `<c r="${target}"/>`))
  if (mutated === worksheet) fail(`UAT-08 fixture could not blank ${target}`)
  entries.set(worksheetName, Buffer.from(mutated))
  return zipXlsx(entries)
}

function parseXlsx(buffer) {
  const zip = zipEntries(buffer)
  const shared = [...(zip.get('xl/sharedStrings.xml')?.toString('utf8').matchAll(/<si>([\s\S]*?)<\/si>/g) ?? [])].map((match) => xmlDecode([...match[1].matchAll(/<t[^>]*>([\s\S]*?)<\/t>/g)].map((part) => part[1]).join('')))
  const sheet = zip.get('xl/worksheets/sheet1.xml')?.toString('utf8')
  if (!sheet) throw new Error('XLSX first worksheet missing')
  const rows = []
  for (const rowMatch of sheet.matchAll(/<row[^>]*>([\s\S]*?)<\/row>/g)) {
    const cells = {}
    for (const cellMatch of rowMatch[1].matchAll(/<c\s+([^>]*)>([\s\S]*?)<\/c>/g)) {
      const attrs = cellMatch[1]
      const ref = /\br="([A-Z]+)\d+"/.exec(attrs)?.[1]
      if (!ref) continue
      const value = /<v>([\s\S]*?)<\/v>/.exec(cellMatch[2])?.[1] ?? ''
      const type = /\bt="([^"]+)"/.exec(attrs)?.[1]
      cells[ref] = type === 's' ? (shared[Number(value)] ?? '') : type === 'inlineStr' ? xmlDecode(cellMatch[2].replace(/[\s\S]*?<t[^>]*>|<\/t>[\s\S]*/g, '')) : (value === '' ? null : Number.isFinite(Number(value)) ? Number(value) : xmlDecode(value))
    }
    rows.push(cells)
  }
  const letters = (index) => { let result = ''; for (let value = index; value >= 0; value = Math.floor(value / 26) - 1) result = String.fromCharCode((value % 26) + 65) + result; return result }
  const headers = Object.keys(rows[0] ?? {}).sort((left, right) => letters(Object.keys(rows[0]).indexOf(left)).localeCompare(letters(Object.keys(rows[0]).indexOf(right))))
  return { headers: headers.map((key) => String(rows[0][key] ?? '')), rows: rows.slice(1).map((row) => Object.fromEntries(headers.map((key, index) => [String(rows[0][key] ?? index), row[key] ?? null]))) }
}

function sha256(value) { return createHash('sha256').update(value).digest('hex') }
function canonical(value) { if (Array.isArray(value)) return `[${value.map(canonical).join(',')}]`; if (value && typeof value === 'object') return `{${Object.keys(value).sort((a, b) => Buffer.from(a).compare(Buffer.from(b))).map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`; return JSON.stringify(value) ?? 'null' }
function fail(message) { throw new Error(message) }

const file = resolve(fileArg)
const originalBytes = readFileSync(file)
const originalDigest = sha256(originalBytes)
const manifest = JSON.parse(readFileSync(MANIFEST, 'utf8')).find((entry) => entry.file_name === basename(file))
if (!manifest) fail('Manifest entry not found for target file')
if (originalDigest !== manifest.sha256) fail('File SHA-256 does not match CONTROL_MANIFEST.json')
const originalParsed = parseXlsx(originalBytes)
if (originalParsed.rows.length !== manifest.total_data_rows) fail(`Manifest row count ${manifest.total_data_rows} != parsed ${originalParsed.rows.length}`)
if (invalidRequiredField && resumeBatchId) fail('UAT-08 invalid fixture cannot be resumed')
const bytes = invalidRequiredField ? createInvalidRequiredFieldFixture(originalBytes, originalParsed.headers, invalidRequiredField) : originalBytes
const digest = sha256(bytes)
const parsed = parseXlsx(bytes)
if (parsed.rows.length !== manifest.total_data_rows) fail(`Manifest row count ${manifest.total_data_rows} != parsed ${parsed.rows.length}`)
if (isDryRun) {
  console.log(JSON.stringify({ mode: 'dry-run', file, sha256: digest, sheet: manifest.sheet_names[0], headers: parsed.headers, rows: parsed.rows.length, controlTotals: manifest.numeric_sums, uat_08_invalid_required_field: invalidRequiredField ?? null, mutated_first_row_value: invalidRequiredField ? parsed.rows[0]?.[invalidRequiredField] ?? null : null }, null, 2))
  process.exit(0)
}
if (!args.has('--confirm-live') || !isLive) { usage(); fail('LIVE guard: require --confirm-live and LIVE project URL') }
const url = process.env.PACKAGE01_LIVE_SUPABASE_URL
const key = process.env.PACKAGE01_LIVE_SUPABASE_PUBLISHABLE_KEY
const email = process.env.PACKAGE01_LIVE_ADMIN_EMAIL
let adminEmail = email
let adminPassword = process.env.PACKAGE01_LIVE_ADMIN_PASSWORD
if (!url || !key) fail('Missing approved LIVE runtime env (URL and publishable key)')
if (!adminEmail || !adminPassword) {
  const prompt = createInterface({ input, output })
  adminEmail ??= await prompt.question('LIVE admin email: ')
  adminPassword ??= await prompt.question('LIVE admin password: ')
  prompt.close()
}
if (!adminEmail || !adminPassword) fail('LIVE admin credentials were not supplied')
const client = createClient(url, key)
const auth = await client.auth.signInWithPassword({ email: adminEmail, password: adminPassword })
if (auth.error || !auth.data.user) fail(`Admin sign-in failed: ${auth.error?.message ?? 'unknown error'}`)
const started = new Date().toISOString()
const headers = parsed.headers
const requiredFields = JSON.parse(process.env.PACKAGE01_LIVE_REQUIRED_FIELDS ?? JSON.stringify(headers))
const controlFields = JSON.parse(process.env.PACKAGE01_LIVE_CONTROL_TOTAL_FIELDS ?? JSON.stringify(Object.fromEntries(Object.keys(manifest.numeric_sums).map((name) => [name, name]))))
const controlScales = JSON.parse(process.env.PACKAGE01_LIVE_CONTROL_TOTAL_SCALES ?? JSON.stringify(Object.fromEntries(Object.keys(controlFields).map((name) => [name, /lt/i.test(name) ? 2 : 0]))))
async function retry(label, operation) {
  let lastError
  for (let attempt = 1; attempt <= 3; attempt += 1) {
    const result = await operation()
    if (!result.error) return result
    lastError = result.error
    if (attempt < 3) await new Promise((resolveDelay) => setTimeout(resolveDelay, attempt * 500))
  }
  fail(`${label} failed after 3 attempts: ${lastError?.message ?? 'unknown error'}`)
}
const contract = await retry('register_source_contract', () => client.rpc('register_source_contract', { p_source_kind: 'TICARI_STOK', p_version: process.env.PACKAGE01_LIVE_CONTRACT_VERSION ?? 'UAT-20260809-10K', p_required_sheet: manifest.sheet_names[0], p_required_headers: headers, p_required_fields: requiredFields, p_control_total_fields: controlFields, p_control_total_scales: controlScales, p_publication_mode: 'FULL_REPLACE' }))
if (contract.error) fail(contract.error.message)
const scope = process.env.PACKAGE01_LIVE_SCOPE ?? (invalidRequiredField ? 'uat-package-01-ticari-stok-10k-interrupt-01' : 'uat-package-01-ticari-stok-10k')
const expectedUat08ActivePublicationId = '7e029c85-976b-4358-a159-0f7f234d5689'
const headBeforeUat08 = invalidRequiredField
  ? await client.from('publication_heads').select('active_publication_id, version').eq('source_kind', 'TICARI_STOK').eq('scope_key', scope).maybeSingle()
  : null
const publicationsBeforeUat08 = invalidRequiredField
  ? await client.from('publications').select('id', { count: 'exact', head: true }).eq('source_kind', 'TICARI_STOK').eq('scope_key', scope)
  : null
if (headBeforeUat08?.error) fail(headBeforeUat08.error.message)
if (publicationsBeforeUat08?.error) fail(publicationsBeforeUat08.error.message)
if (invalidRequiredField && headBeforeUat08.data?.active_publication_id !== expectedUat08ActivePublicationId) fail(`UAT-08 precondition failed: expected active publication ${expectedUat08ActivePublicationId}, got ${headBeforeUat08.data?.active_publication_id ?? 'none'}`)
let batchRecord
if (resumeBatchId) {
  const resumed = await client.from('import_batches').select('*').eq('id', resumeBatchId).maybeSingle()
  if (resumed.error || !resumed.data) fail(`Resume batch lookup failed: ${resumed.error?.message ?? 'batch not found'}`)
  if (resumed.data.scope_key !== scope || resumed.data.declared_file_hash !== digest) fail('Resume batch scope or file hash does not match the selected synthetic UAT file')
  batchRecord = resumed.data
} else {
  const batch = await retry('create_import_batch', () => client.rpc('create_import_batch', { p_source_contract_version_id: contract.data, p_scope_key: scope, p_source_sheet: manifest.sheet_names[0], p_source_headers: headers, p_file_hash: digest, p_file_size_bytes: bytes.length, p_expected_rows: parsed.rows.length, p_expected_chunks: Math.ceil(parsed.rows.length / CHUNK_SIZE), p_expected_control_totals: manifest.numeric_sums }))
  if (batch.error) fail(batch.error.message)
  batchRecord = Array.isArray(batch.data) ? batch.data[0] : batch.data
}
if (!batchRecord?.id || !batchRecord.storage_object_path) fail('create_import_batch returned no usable batch record')
const batchId = batchRecord.id
if (!resumeBatchId) {
  let temporaryFixturePath
  if (invalidRequiredField) {
    temporaryFixturePath = resolve('artifacts', `uat-08-invalid-${Date.now()}.xlsx`)
    mkdirSync(dirname(temporaryFixturePath), { recursive: true })
    writeFileSync(temporaryFixturePath, bytes, { flag: 'wx' })
  }
  try {
    const upload = await client.storage.from('source-evidence').upload(batchRecord.storage_object_path, bytes, { upsert: false, contentType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' })
    if (upload.error) fail(upload.error.message)
    const verify = await fetch(`${url}/functions/v1/verify-import-source`, { method: 'POST', headers: { Authorization: `Bearer ${auth.data.session.access_token}`, apikey: key, 'content-type': 'application/json' }, body: JSON.stringify({ batchId }) })
    if (!verify.ok) fail(`verify-import-source failed: HTTP ${verify.status}`)
  } finally {
    if (temporaryFixturePath) unlinkSync(temporaryFixturePath)
  }
}
const existingBefore = await client.from('import_chunks').select('chunk_no').eq('batch_id', batchId)
if (existingBefore.error) fail(existingBefore.error.message)
const existingChunkNos = new Set((existingBefore.data ?? []).map((row) => row.chunk_no))
let retriedChunks = 0
for (let offset = 0, chunkNo = 0; offset < parsed.rows.length; offset += CHUNK_SIZE, chunkNo += 1) {
  const rows = parsed.rows.slice(offset, offset + CHUNK_SIZE)
  const payload = rows.map((row) => ({ ...row }))
  const chunk = await retry(`stage_import_chunk ${chunkNo}`, () => client.rpc('stage_import_chunk', { p_batch_id: batchId, p_chunk_no: chunkNo, p_row_offset: offset, p_chunk_hash: sha256(canonical(payload)), p_row_count: payload.length, p_rows: payload }))
  if (chunk.error) fail(chunk.error.message)
  if (existingChunkNos.has(chunkNo)) retriedChunks += 1
  if (!resumeBatchId && Number.isInteger(interruptAfter) && interruptAfter > 0 && chunkNo + 1 >= interruptAfter) {
    await client.auth.signOut()
    console.log(JSON.stringify({ result: 'INTERRUPTED', batch_id: batchId, interrupted_after_chunk: chunkNo, chunks_staged: chunkNo + 1, retried_chunks: 0 }, null, 2))
    process.exit(0)
  }
}
const validation = await retry('validate_import_batch', () => client.rpc('validate_import_batch', { p_batch_id: batchId }))
const reconciliation = await retry('reconcile_import_batch', () => client.rpc('reconcile_import_batch', { p_batch_id: batchId }))
if (invalidRequiredField) {
  const batchAfter = await client.from('import_batches').select('status, published_publication_id').eq('id', batchId).maybeSingle()
  const validationRun = await client.from('validation_runs').select('status, valid_rows, blocked_rows, duplicate_rows').eq('id', validation.data).maybeSingle()
  const reconciliationRun = await client.from('import_reconciliations').select('status, expected_control_totals, actual_control_totals, blocked_rows').eq('id', reconciliation.data).maybeSingle()
  const candidate = await client.rpc('create_candidate_publication', { p_batch_id: batchId, p_manifest: { file: basename(file), sha256: digest, rows: parsed.rows.length, controlTotals: manifest.numeric_sums, uat_08_invalid_required_field: invalidRequiredField } })
  const headAfter = await client.from('publication_heads').select('active_publication_id, version').eq('source_kind', 'TICARI_STOK').eq('scope_key', scope).maybeSingle()
  const publicationsAfter = await client.from('publications').select('id', { count: 'exact', head: true }).eq('source_kind', 'TICARI_STOK').eq('scope_key', scope)
  const activePublication = await client.from('publications').select('candidate_id').eq('id', expectedUat08ActivePublicationId).maybeSingle()
  const activeCandidate = activePublication.data?.candidate_id
    ? await client.from('candidate_publications').select('batch_id').eq('id', activePublication.data.candidate_id).maybeSingle()
    : { data: null, error: new Error('active publication lookup failed') }
  const publishedRows = activeCandidate.data?.batch_id
    ? await client.from('staging_rows').select('id', { count: 'exact', head: true }).eq('batch_id', activeCandidate.data.batch_id).eq('row_status', 'VALID')
    : { count: null, error: new Error('active publication candidate lookup failed') }
  if (batchAfter.error || validationRun.error || reconciliationRun.error || headAfter.error || publicationsAfter.error || activePublication.error || activeCandidate.error || publishedRows.error) fail('UAT-08 evidence read failed')
  const candidateBlocked = Boolean(candidate.error) && /Only exactly reconciled batches can become candidates/i.test(candidate.error.message)
  const preserved = headAfter.data?.active_publication_id === expectedUat08ActivePublicationId
  const publicationCreated = publicationsAfter.count !== publicationsBeforeUat08.count
  const passed = validationRun.data?.status === 'BLOCKED' && reconciliationRun.data?.status === 'MISMATCHED' && candidateBlocked && !publicationCreated && preserved && batchAfter.data?.published_publication_id === null && publishedRows.count === 10000
  console.log(JSON.stringify({ result: passed ? 'PASS' : 'FAIL', uat: 'UAT-08', batch_id: batchId, invalid_required_field: invalidRequiredField, block_reason: candidate.error?.message ?? 'candidate unexpectedly created', validation: validationRun.data, reconciliation: reconciliationRun.data, publication_created: publicationCreated, active_publication_before: headBeforeUat08.data?.active_publication_id ?? null, active_publication_after: headAfter.data?.active_publication_id ?? null, preserved, published_row_state_preservation: { active_publication_id: expectedUat08ActivePublicationId, valid_staging_rows: publishedRows.count }, batch_status: batchAfter.data?.status ?? null }, null, 2))
  await client.auth.signOut()
  process.exit(passed ? 0 : 1)
}
const candidate = await retry('create_candidate_publication', () => client.rpc('create_candidate_publication', { p_batch_id: batchId, p_manifest: { file: basename(file), sha256: digest, rows: parsed.rows.length, controlTotals: manifest.numeric_sums } }))
const head = await client.from('publication_heads').select('active_publication_id, version').eq('source_kind', 'TICARI_STOK').eq('scope_key', scope).maybeSingle(); if (head.error) fail(head.error.message)
const publication = await retry('publish_candidate', () => client.rpc('publish_candidate', { p_candidate_id: candidate.data, p_expected_active_publication_id: head.data?.active_publication_id ?? null }))
const counts = await client.from('staging_rows').select('row_status', { count: 'exact' }).eq('batch_id', batchId)
const chunkCount = await client.from('import_chunks').select('chunk_no', { count: 'exact' }).eq('batch_id', batchId)
const publicationCount = await client.from('publications').select('id', { count: 'exact' }).eq('source_kind', 'TICARI_STOK').eq('scope_key', scope)
const headAfter = await client.from('publication_heads').select('active_publication_id, version').eq('source_kind', 'TICARI_STOK').eq('scope_key', scope).maybeSingle()
console.log(JSON.stringify({ result: 'PASS', batch_id: batchId, publication_id: publication.data, started_at: started, finished_at: new Date().toISOString(), rows_parsed: parsed.rows.length, chunks: chunkCount.count, retried_chunks: retriedChunks, staging_rows: counts.count, publications_in_scope: publicationCount.count, previous_active_publication_id: head.data?.active_publication_id ?? null, final_active_publication_id: headAfter.data?.active_publication_id ?? null, final_version: headAfter.data?.version ?? null, reconciliation: 'MATCHED', control_totals: manifest.numeric_sums }, null, 2))
await client.auth.signOut()
