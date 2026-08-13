import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import * as XLSX from 'xlsx'
import type { ApplicationRole } from '@dealer-operations/contracts'
import { DEFAULT_IMPORT_CHUNK_SIZE, type ImportWorkerResponse } from './lib/import-worker-protocol'
import { parseSourceMatrix } from './lib/source-parser'
import {
  createCandidate,
  createImportBatch,
  getAdminBatchDetail,
  listAdminBatches,
  listPublicationHeads,
  listPublishedHistory,
  listSourceContracts,
  publishCandidate,
  reconcileBatch,
  sourceObjectExists,
  stageChunk,
  uploadSource,
  validateBatch,
  verifySource,
  type BatchDetail,
  type ImportBatch,
  type Publication,
  type PublicationHead,
  type ValidationIssue,
  type SourceContract,
} from './lib/import-api'

type UploadStatus = 'EMPTY' | 'RECOGNIZING' | 'READY' | 'UPLOADING' | 'STAGING' | 'VALIDATING' | 'RECONCILING' | 'CANDIDATE' | 'PUBLISHED' | 'FAILED' | 'DUPLICATE' | 'STALE' | 'UNSUPPORTED'
type ParsedSource = { contract: SourceContract; sheet: string; headers: string[]; rows: Record<string, unknown>[]; expectedControlTotals: Record<string, string> }
type UploadQueueItem = { id: string; file: File; parsed: ParsedSource | null; scopeOverride: string; scopeOverrideOpen: boolean; batchId?: string; batch?: ImportBatch; status: UploadStatus; progress: number; progressText: string; error: string }
type SummaryState = 'SUCCESS' | 'MISSING' | 'EMPTY' | 'FAILED' | 'UNSUPPORTED' | 'INFO'
type QueueSummary = { value: string; detail: string; state: SummaryState }

const statusLabels: Record<string, string> = {
  EMPTY: 'Dosya bekleniyor', RECOGNIZING: 'Kaynak tanınıyor', UPLOADING: 'Dosya yükleniyor', STAGING: 'Satırlar staging alanına alınıyor',
  VALIDATING: 'Satırlar doğrulanıyor', RECONCILING: 'Uzlaştırma yapılıyor', CANDIDATE: 'Yayın onayı bekleniyor', PUBLISHED: 'Yayınlandı',
  FAILED: 'İşlem bloklandı', DUPLICATE: 'Duplicate yükleme engellendi', STALE: 'Server durumu yenilenmeli',
}
const statusMachine: Record<string, string> = {
  EMPTY: 'EMPTY', RECOGNIZING: 'SOURCE_CHECK', UPLOADING: 'UPLOADING', STAGING: 'STAGING', VALIDATING: 'VALIDATING',
  RECONCILING: 'RECONCILING', CANDIDATE: 'CANDIDATE_READY', PUBLISHED: 'PUBLISHED', FAILED: 'FAILED', DUPLICATE: 'DUPLICATE', STALE: 'STALE',
}
statusLabels.RECOGNIZING = 'Kaynak kontrol ediliyor'
statusLabels.READY = 'Kaynak tanındı'
statusLabels.UNSUPPORTED = 'Kaynak sözleşmesi henüz aktif değil'
statusMachine.RECOGNIZING = 'SOURCE_CHECK'
statusMachine.READY = 'READY'
statusMachine.UNSUPPORTED = 'UNSUPPORTED'
function display(value: unknown) { return value === null || value === undefined || value === '' ? '—' : String(value) }
function number(value: unknown) { return typeof value === 'number' && Number.isFinite(value) ? value.toLocaleString('tr-TR') : '—' }
function formatDate(value: string | null | undefined) { return value ? new Intl.DateTimeFormat('tr-TR', { dateStyle: 'short', timeStyle: 'short' }).format(new Date(value)) : '—' }
function statusForBatch(batch: ImportBatch): UploadStatus {
  if (batch.status === 'PUBLISHED') return 'PUBLISHED'
  if (batch.status === 'CANDIDATE_READY') return 'CANDIDATE'
  if (batch.status === 'FAILED') return 'FAILED'
  if (batch.status === 'STAGING') return 'STAGING'
  if (batch.status === 'VALIDATED') return 'VALIDATING'
  if (batch.status === 'RECONCILED') return 'RECONCILING'
  if (batch.status === 'CREATED') return 'STAGING'
  return 'RECOGNIZING'
}
function summaryStateForStatus(status: UploadStatus): SummaryState {
  if (status === 'FAILED') return 'FAILED'
  if (status === 'UNSUPPORTED') return 'UNSUPPORTED'
  if (status === 'EMPTY') return 'EMPTY'
  return 'SUCCESS'
}
function errorText(error: unknown) {
  if (error instanceof Error) return error.message
  if (typeof error === 'object' && error !== null && 'message' in error && typeof error.message === 'string') return error.message
  if (typeof error === 'string' && error.trim()) return error
  return 'İşlem tamamlanamadı.'
}
class UnsupportedSourceError extends Error { constructor() { super('Bu kaynak türü için henüz aktif bir kaynak sözleşmesi bulunmuyor.'); this.name = 'UnsupportedSourceError' } }

async function fileHash(file: File) {
  const digest = await crypto.subtle.digest('SHA-256', await file.arrayBuffer())
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, '0')).join('')
}

async function waitForStagedBatch(batchId: string, expectedChunks: number, expectedRows: number) {
  let latest: BatchDetail | null = null
  for (let attempt = 0; attempt < 4; attempt += 1) {
    latest = await getAdminBatchDetail(batchId)
    if (latest.batch.received_chunks >= expectedChunks && latest.batch.staged_rows >= expectedRows) return latest
    await new Promise((resolve) => setTimeout(resolve, 150))
  }
  throw new Error(`Staging tamamlandı doğrulanamadı: ${latest?.batch.received_chunks ?? 0}/${expectedChunks} chunk, ${latest?.batch.staged_rows ?? 0}/${expectedRows} satır.`)
}

async function recognizeSource(file: File, contracts: SourceContract[]): Promise<ParsedSource> {
  const workbook = XLSX.read(await file.arrayBuffer(), { type: 'array', cellDates: false, raw: true })
  for (const contract of contracts) {
    if (!workbook.SheetNames.includes(contract.requiredSheet)) continue
    const sheet = workbook.Sheets[contract.requiredSheet]
    const matrix = XLSX.utils.sheet_to_json<unknown[]>(sheet, { header: 1, defval: null, raw: true })
    const { headers, rows } = parseSourceMatrix(matrix)
    if (!contract.requiredHeaders.every((header) => headers.includes(header))) continue
    const expectedControlTotals = Object.fromEntries(Object.entries(contract.controlTotalFields).map(([metric, field]) => {
      const scale = contract.controlTotalScales[metric]
      const total = rows.reduce((sum, row) => sum + (Number(row[field]) || 0), 0)
      return [metric, scale === 0 ? String(Math.round(total)) : total.toFixed(scale)]
    }))
    return { contract, sheet: contract.requiredSheet, headers, rows, expectedControlTotals }
  }
  throw new UnsupportedSourceError()
}

function buildChunks(rows: Record<string, unknown>[], batchId: string, onProgress: (current: number, total: number) => void) {
  return new Promise<{ batchId: string; chunkNo: number; rowOffset: number; chunkHash: string; rowCount: number; rows: Record<string, unknown>[] }[]>((resolve, reject) => {
    const worker = new Worker(new URL('./workers/import-chunk.worker.ts', import.meta.url), { type: 'module' })
    const chunks: { batchId: string; chunkNo: number; rowOffset: number; chunkHash: string; rowCount: number; rows: Record<string, unknown>[] }[] = []
    worker.onmessage = (event: MessageEvent<ImportWorkerResponse>) => {
      if (event.data.type === 'CHUNK') { chunks.push(event.data.chunk); onProgress(chunks.length, Math.ceil(rows.length / DEFAULT_IMPORT_CHUNK_SIZE)) }
      if (event.data.type === 'COMPLETE') { worker.terminate(); resolve(chunks.sort((left, right) => left.chunkNo - right.chunkNo)) }
      if (event.data.type === 'ERROR') { worker.terminate(); reject(new Error(event.data.message)) }
    }
    worker.onerror = () => { worker.terminate(); reject(new Error('Dosya satırları hazırlanamadı.')) }
    worker.postMessage({ type: 'BUILD_CHUNKS', batchId, rows, chunkSize: DEFAULT_IMPORT_CHUNK_SIZE })
  })
}

function MultiFileAdminUpload({ contracts, batches, onRefresh, onQueueState }: { contracts: SourceContract[]; batches: ImportBatch[]; onRefresh: () => void; onQueueState: (summary: QueueSummary) => void }) {
  const inputRef = useRef<HTMLInputElement>(null)
  const [items, setItems] = useState<UploadQueueItem[]>([])
  const [defaultScope, setDefaultScope] = useState('')
  const processing = useRef(new Set<string>())

  useEffect(() => {
    if (!batches.length) return
    setItems((current) => current.map((item) => {
      const batch = item.batchId ? batches.find((candidate) => candidate.id === item.batchId) : null
      if (!batch) return item
      if (item.status === 'FAILED' && batch.status !== 'FAILED') return item
      if (['STAGING', 'VALIDATING', 'RECONCILING'].includes(item.status) && ['CREATED', 'AWAITING_SOURCE_VERIFICATION', 'STAGING'].includes(batch.status)) return item
      const nextStatus = statusForBatch(batch)
      return { ...item, status: nextStatus, progress: nextStatus === 'PUBLISHED' ? 100 : item.progress, progressText: nextStatus === 'PUBLISHED' ? 'Yayınlandı' : item.progressText }
    }))
  }, [batches])

  useEffect(() => {
    if (!items.length) { onQueueState({ value: '—', detail: 'Kuyruk boş', state: 'EMPTY' }); return }
    const statuses = items.map((item) => item.status)
    const unsupported = statuses.filter((status) => status === 'UNSUPPORTED').length
    const failed = statuses.filter((status) => status === 'FAILED').length
    const ready = statuses.filter((status) => status === 'READY').length
    const active = statuses.some((status) => ['RECOGNIZING', 'UPLOADING', 'STAGING', 'VALIDATING', 'RECONCILING'].includes(status))
    if (unsupported && (ready || failed || active)) { onQueueState({ value: 'MIXED', detail: `${ready} READY · ${unsupported} UNSUPPORTED`, state: 'INFO' }); return }
    if (active) { onQueueState({ value: 'Kuyruk işleniyor', detail: 'Aktif dosya işlemi devam ediyor', state: 'INFO' }); return }
    if (failed) { onQueueState({ value: 'İşlem bloklandı', detail: `${failed} dosya FAILED`, state: 'FAILED' }); return }
    if (unsupported === statuses.length) { onQueueState({ value: 'Kaynak sözleşmesi henüz aktif değil', detail: `${unsupported} dosya UNSUPPORTED`, state: 'UNSUPPORTED' }); return }
    if (ready) { onQueueState({ value: 'Kuyruk hazır', detail: `${ready} dosya READY`, state: 'SUCCESS' }); return }
    onQueueState({ value: 'Kuyruk tamamlandı', detail: 'İşlenen dosyalar güncel', state: 'SUCCESS' })
  }, [items, onQueueState])

  const updateItem = useCallback((id: string, patch: Partial<UploadQueueItem>) => {
    setItems((current) => current.map((item) => item.id === id ? { ...item, ...patch } : item))
  }, [])

  async function recognizeItem(item: UploadQueueItem) {
    try {
      const parsed = await recognizeSource(item.file, contracts)
      updateItem(item.id, { parsed, status: 'READY', progress: 0, progressText: 'Kaynak tanındı', error: '' })
    } catch (error) {
      updateItem(item.id, { status: error instanceof UnsupportedSourceError ? 'UNSUPPORTED' : 'FAILED', progress: 0, progressText: '', error: errorText(error) })
    }
  }

  function addFiles(files: File[]) {
    const accepted = files.filter((file) => /\.(xlsx|xls)$/i.test(file.name))
    if (!accepted.length) return
    const added = accepted.map((file, index) => ({ id: `${Date.now()}-${index}-${Math.random().toString(36).slice(2)}`, file, parsed: null, scopeOverride: '', scopeOverrideOpen: false, status: 'RECOGNIZING' as UploadStatus, progress: 0, progressText: 'Kaynak kontrol ediliyor', error: '' }))
    setItems((current) => [...current, ...added])
    void Promise.all(added.map((item) => recognizeItem(item)))
  }

  function resetItem(item: UploadQueueItem) {
    updateItem(item.id, { parsed: null, status: 'RECOGNIZING', progress: 0, progressText: 'Kaynak kontrol ediliyor', error: '' })
    void recognizeItem({ ...item, parsed: null, status: 'RECOGNIZING', progress: 0, progressText: 'Kaynak kontrol ediliyor', error: '' })
  }

  function removeItem(id: string) { setItems((current) => current.filter((item) => item.id !== id)) }
  function setScope(id: string, scopeOverride: string) { updateItem(id, { scopeOverride }) }
  function toggleScopeOverride(id: string) { setItems((current) => current.map((item) => item.id === id ? { ...item, scopeOverrideOpen: !item.scopeOverrideOpen } : item)) }

  async function processItem(itemId: string) {
    if (processing.current.has(itemId)) return
    const item = items.find((candidate) => candidate.id === itemId)
    const effectiveScope = item?.scopeOverride.trim() || defaultScope.trim()
    if (!item || item.status !== 'READY' || !item.parsed || !effectiveScope) {
      if (item?.status === 'READY') updateItem(itemId, { error: 'Yayın kapsamını girin.' })
      return
    }
    processing.current.add(itemId)
    try {
      updateItem(itemId, { status: 'UPLOADING', progress: 5, progressText: 'Batch oluşturuluyor', error: '' })
      const hash = await fileHash(item.file)
      const existingBatch = item.batch && item.batch.declared_file_hash === hash
        ? item.batch
        : batches.find((candidate) => candidate.declared_file_hash === hash && candidate.source_contract_version_id === item.parsed?.contract.id && candidate.scope_key === effectiveScope)
      const batch = existingBatch ?? await createImportBatch({ contractId: item.parsed.contract.id, scopeKey: effectiveScope, sourceSheet: item.parsed.sheet, sourceHeaders: item.parsed.headers, fileHash: hash, fileSize: item.file.size, expectedRows: item.parsed.rows.length, expectedChunks: Math.ceil(item.parsed.rows.length / DEFAULT_IMPORT_CHUNK_SIZE), expectedControlTotals: item.parsed.expectedControlTotals })
      const resuming = Boolean(existingBatch)
      updateItem(itemId, { batchId: batch.id, batch, progressText: resuming ? 'Devam eden batch bulundu, devam ediliyor' : 'Batch oluşturuldu' })
      if (['PUBLISHING', 'PUBLISHED', 'CANDIDATE_READY'].includes(batch.status)) {
        updateItem(itemId, { status: 'DUPLICATE', progress: 100, progressText: 'Mevcut batch korunuyor', error: 'Bu dosya aynı kapsamda daha önce işlendi.' })
        return
      }
      if (batch.status === 'FAILED') {
        updateItem(itemId, { status: 'FAILED', progressText: '', error: 'Mevcut batch FAILED durumda; yeni bir kaynak kanıtı gerekir.' })
        return
      }
      const sourceVerified = Boolean(batch.source_verified_at)
      if (!sourceVerified) {
        const objectExists = resuming && await sourceObjectExists(batch)
        if (!objectExists) await uploadSource(batch, item.file)
        updateItem(itemId, { progress: 15, progressText: objectExists ? 'Mevcut kaynak doğrulanıyor' : 'Kaynak server tarafından doğrulanıyor' })
        await verifySource(batch.id)
      } else {
        updateItem(itemId, { progress: 15, progressText: 'Kaynak zaten doğrulandı; devam ediliyor' })
      }
      if (!['VALIDATED', 'RECONCILED'].includes(batch.status)) {
        updateItem(itemId, { status: 'STAGING', progress: 20, progressText: 'Satırlar staging alanına alınıyor' })
        const chunks = await buildChunks(item.parsed.rows, batch.id, (current, total) => updateItem(itemId, { progress: 20 + Math.round((current / Math.max(total, 1)) * 55), progressText: `${current} / ${total} chunk staging’e alındı` }))
        for (const chunk of chunks) await stageChunk(chunk)
        await waitForStagedBatch(batch.id, batch.expected_chunks, batch.expected_rows)
        updateItem(itemId, { status: 'VALIDATING', progress: 80, progressText: 'Satırlar doğrulanıyor' })
        await validateBatch(batch.id)
      }
      if (batch.status !== 'RECONCILED') {
        updateItem(itemId, { status: 'RECONCILING', progress: 90, progressText: 'Control totals uzlaştırılıyor' })
        await reconcileBatch(batch.id)
      }
      await createCandidate(batch.id, { source: item.parsed.contract.sourceKind, scopeKey: effectiveScope, fileName: item.file.name })
      updateItem(itemId, { status: 'CANDIDATE', progress: 100, progressText: 'Candidate hazır; admin onayı bekleniyor' })
      onRefresh()
    } catch (error) {
      updateItem(itemId, { status: 'FAILED', progressText: '', error: errorText(error) })
      onRefresh()
    } finally { processing.current.delete(itemId) }
  }

  async function processReady() {
    const readyIds = items.filter((item) => item.status === 'READY' && (item.scopeOverride.trim() || defaultScope.trim())).map((item) => item.id)
    for (const id of readyIds) await processItem(id)
  }

  return <section className="upload-workbench queue-workbench"><div className="surface-card upload-card"><div className="section-heading"><div><h2>Yeni yükleme kuyruğu</h2><p>Her dosya ayrı tanınır, hash’lenir ve Package 01 batch akışından ilerler.</p></div><button className="primary-button" type="button" onClick={() => void processReady()} disabled={!items.some((item) => item.status === 'READY' && (item.scopeOverride.trim() || defaultScope.trim()))}>Hazır dosyaları başlat</button></div><label className="queue-default-scope">Varsayılan yayın kapsamı<input value={defaultScope} onChange={(event) => setDefaultScope(event.target.value)} placeholder="Tüm READY dosyalar için kapsam" /></label><div className="dropzone" onDragOver={(event) => event.preventDefault()} onDrop={(event) => { event.preventDefault(); addFiles(Array.from(event.dataTransfer.files)) }}><span className="upload-icon" aria-hidden="true">↑</span><h3>Dosyaları buraya sürükleyin veya seçin</h3><p>10–12 XLSX dosyası · Her dosya ayrı batch olarak işlenir</p><input ref={inputRef} type="file" accept=".xlsx,.xls" multiple hidden onChange={(event) => { addFiles(Array.from(event.target.files ?? [])); event.target.value = '' }} /><button className="primary-button" type="button" onClick={() => inputRef.current?.click()}>Dosyaları seç</button></div>{items.length ? <div className="upload-queue" aria-label="Yükleme kuyruğu">{items.map((item) => { const effectiveScope = item.scopeOverride.trim() || defaultScope.trim(); return <article className="queue-item" key={item.id}><div className="queue-item-head"><div><strong>{item.file.name}</strong><small>{(item.file.size / 1048576).toFixed(2)} MB{item.parsed ? ` · ${item.parsed.contract.sourceKind} v${item.parsed.contract.version}` : ''}</small></div><span className={`state-badge ${item.status.toLowerCase()}`}>{statusLabels[item.status]} · {statusMachine[item.status]}</span></div>{item.parsed ? <div className="queue-scope-row"><span>{effectiveScope || 'Varsayılan kapsam girilmedi'}</span>{item.scopeOverride ? <span className="scope-override-badge">Override</span> : null}<button className="link-button" type="button" onClick={() => toggleScopeOverride(item.id)}>{item.scopeOverrideOpen ? 'Kapsamı kapat' : 'Kapsamı değiştir'}</button></div> : null}{item.scopeOverrideOpen ? <label className="scope-field">Dosya kapsamı override<input value={item.scopeOverride} onChange={(event) => setScope(item.id, event.target.value)} placeholder="Bu dosya için özel kapsam" /></label> : null}<div className="queue-progress"><div className="progress-track"><span style={{ width: `${item.progress}%` }} /></div><small>{item.progressText || (item.status === 'READY' ? 'Kaynak tanındı; kapsam bekleniyor' : '')}</small></div>{item.error ? <div className={`notice ${item.status === 'UNSUPPORTED' ? 'unsupported-notice' : 'error'}`} role="alert">{item.error}</div> : null}<div className="queue-actions">{item.status === 'READY' ? <><button className="publish-button" type="button" disabled={!effectiveScope} aria-label={effectiveScope ? 'Bu dosyayı başlat' : 'Başlatmak için kapsam girin'} onClick={() => void processItem(item.id)}>Bu dosyayı başlat</button>{!effectiveScope ? <small className="queue-action-hint">Başlatmak için varsayılan kapsam girin veya dosya kapsamı override açın.</small> : null}</> : null}{['FAILED', 'DUPLICATE', 'STALE', 'UNSUPPORTED'].includes(item.status) ? <button className="secondary-button" type="button" onClick={() => resetItem(item)}>Tekrar dene</button> : null}<button className="link-button" type="button" onClick={() => removeItem(item.id)}>Kuyruktan çıkar</button></div></article> })}</div> : <p className="queue-empty">Henüz dosya seçilmedi.</p>}</div><aside className="surface-card upload-guardrail"><h3>Aktif yayın korunur</h3><p>Bir dosyanın hatası diğer kuyruk öğelerini durdurmaz. Her dosya mevcut tek-dosya Package 01 contract zinciriyle ayrı batch olarak işlenir.</p></aside></section>
}

export function UploadCenter({ role }: { role: ApplicationRole }) {
  const admin = role === 'admin'
  const [contracts, setContracts] = useState<SourceContract[]>([])
  const [batches, setBatches] = useState<ImportBatch[]>([])
  const [publications, setPublications] = useState<Publication[]>([])
  const [heads, setHeads] = useState<PublicationHead[]>([])
  const [message, setMessage] = useState('')
  const [loading, setLoading] = useState(true)
  const [detail, setDetail] = useState<BatchDetail | null>(null)
  const [publishConfirmation, setPublishConfirmation] = useState(false)
  const [publicationDetail, setPublicationDetail] = useState<Publication | null>(null)
  const [publishing, setPublishing] = useState(false)
  const [queueSummary, setQueueSummary] = useState<QueueSummary>({ value: '—', detail: 'Kuyruk boş', state: 'EMPTY' })

  const refresh = useCallback(async () => {
    setLoading(true)
    try {
      if (admin) {
        const [nextContracts, nextBatches, nextHeads, nextPublications] = await Promise.all([listSourceContracts(), listAdminBatches(), listPublicationHeads(), listPublishedHistory()])
        setContracts(nextContracts); setBatches(nextBatches); setHeads(nextHeads); setPublications(nextPublications)
      } else {
        const [nextPublications, nextHeads] = await Promise.all([listPublishedHistory(), listPublicationHeads()])
        setPublications(nextPublications); setHeads(nextHeads)
      }
      setMessage('')
    } catch (error) { setMessage(errorText(error)) } finally { setLoading(false) }
  }, [admin])
  useEffect(() => { void refresh() }, [refresh])

  const latestPublication = publications[0]
  const activePublication = useMemo(() => latestPublication ?? publications.find((publication) => heads.some((head) => head.active_publication_id === publication.id)), [heads, latestPublication, publications])
  const latestBatch = batches[0]
  const parsed = undefined as ParsedSource | undefined
  const onQueueState = useCallback((summary: QueueSummary) => setQueueSummary(summary), [])
  const currentStatusSummary = detail ? { value: statusLabels[statusForBatch(detail.batch)], detail: statusMachine[statusForBatch(detail.batch)], state: summaryStateForStatus(statusForBatch(detail.batch)) } : queueSummary

  async function openBatch(batchId: string) { try { setPublishConfirmation(false); setDetail(await getAdminBatchDetail(batchId)) } catch (error) { setMessage(errorText(error)) } }
  async function confirmPublish() {
    if (!detail?.candidate || publishing) return
    setPublishing(true); setMessage('')
    try {
      const head = heads.find((item) => item.source_kind === detail.batch.source_kind && item.scope_key === detail.batch.scope_key)
      await publishCandidate(detail.candidate.id, head?.active_publication_id ?? null)
      setPublishConfirmation(false); setDetail(null); await refresh()
    } catch (error) { setMessage(errorText(error)) } finally { setPublishing(false) }
  }

  const activeCount = batches.filter((batch) => !['PUBLISHED', 'FAILED'].includes(batch.status)).length
  const blockedCount = batches.filter((batch) => batch.status === 'FAILED').length
  return <>
    <section className="upload-page-head"><div><p className="eyebrow">PACKAGE 01U · UPLOAD CENTER</p><h1 id="page-title">Veri Yükleme Merkezi</h1><p>Excel kaynaklarını tanı, doğrula, uzlaştır ve yalnız hazır olduğunda yayınla. Ekran durumu server-side batch/publication kayıtlarından yeniden oluşturulur.</p></div><span className="role-pill">{admin ? 'Yönetici · Yayın yetkili' : 'Viewer · Salt okunur'}</span></section>
    <section className="upload-summary" aria-label="Upload Center özeti">
      <Summary label="Kaynak sözleşmesi" value={display(parsed?.contract.sourceKind)} detail={parsed?.contract.version ? `v${parsed.contract.version}` : 'Dosya seçildiğinde tanınır'} state={parsed ? 'SUCCESS' : 'MISSING'} />
      <Summary label="Son aktif yayın" value={activePublication ? number(activePublication.version) : '—'} detail={activePublication ? formatDate(activePublication.published_at) : 'Yayın bulunamadı'} state={activePublication ? 'SUCCESS' : 'MISSING'} />
      <Summary label="Toplam kayıt (son aday)" value={latestBatch ? number(latestBatch.expected_rows) : '—'} detail={latestBatch ? latestBatch.source_kind : 'Aday oluşturulmadı'} state={latestBatch ? 'SUCCESS' : 'MISSING'} />
      <Summary label="Durum" value={currentStatusSummary.value} detail={currentStatusSummary.detail} state={currentStatusSummary.state} />
      <Summary label="Reconciliation" value={detail?.reconciliation?.status ?? '—'} detail={detail?.reconciliation ? 'Backend sonucu' : 'Batch detayı seçilmedi'} state={detail?.reconciliation ? 'SUCCESS' : 'MISSING'} />
    </section>
    {admin ? <MultiFileAdminUpload contracts={contracts} batches={batches} onRefresh={() => void refresh()} onQueueState={onQueueState} /> : null}
    {message && !admin ? <div className="notice error" role="alert">{message}</div> : null}
    <section className="upload-lower-grid">
      <article className="surface-card upload-last-summary"><h2>{admin ? 'Son yükleme özeti' : 'Yayın özeti'}</h2>{admin && !latestBatch ? <EmptyState text="Henüz yükleme yapılmadı. Admin hesabıyla dosya seçerek başlayın." /> : <div className="summary-list"><div><span>Son başarılı yayın</span><strong>{activePublication ? formatDate(activePublication.published_at) : '—'}</strong></div><div><span>{admin ? 'Devam ettirilebilir batch' : 'Yayın sayısı'}</span><strong>{admin ? number(activeCount) : number(publications.length)}</strong></div><div><span>{admin ? 'Bloklu batch' : 'Aktif başlık'}</span><strong>{admin ? number(blockedCount) : number(heads.length)}</strong></div></div>}</article>
      <article className="surface-card history-card"><div className="section-heading"><div><h2>{admin ? 'Yükleme geçmişi' : 'Yayın geçmişi'}</h2><p>{admin ? 'Tam operasyon geçmişi ve batch detail yalnız admin içindir.' : 'Yalnız published read surface ve provenance geçmişi gösterilir.'}</p></div><button className="secondary-button" type="button" onClick={() => void refresh()}>{loading ? 'Yükleniyor…' : 'Yenile'}</button></div>{admin ? <AdminHistory batches={batches} onOpen={openBatch} /> : <ViewerHistory publications={publications} onOpen={setPublicationDetail} />}</article>
    </section>
    {detail ? <BatchDrawer detail={detail} confirmation={publishConfirmation} activeHead={heads.find((item) => item.source_kind === detail.batch.source_kind && item.scope_key === detail.batch.scope_key) ?? null} activePublication={publications.find((publication) => publication.id === heads.find((item) => item.source_kind === detail.batch.source_kind && item.scope_key === detail.batch.scope_key)?.active_publication_id) ?? null} onClose={() => { setPublishConfirmation(false); setDetail(null) }} onRequestPublish={() => setPublishConfirmation(true)} onCancelPublish={() => setPublishConfirmation(false)} onConfirmPublish={() => void confirmPublish()} publishing={publishing} /> : null}
    {publicationDetail ? <PublicationDrawer publication={publicationDetail} onClose={() => setPublicationDetail(null)} /> : null}
  </>
}

function Summary({ label, value, detail, state }: { label: string; value: string; detail: string; state: SummaryState }) { return <article className="summary-card"><p>{label}</p><strong>{value}</strong><span className={`state-badge ${state.toLowerCase()}`}>{state}</span><small>{detail}</small></article> }
function EmptyState({ text }: { text: string }) { return <div className="empty-state"><div className="empty-icon" aria-hidden="true">⌁</div><p>{text}</p></div> }
function AdminHistory({ batches, onOpen }: { batches: ImportBatch[]; onOpen: (id: string) => void }) { return batches.length ? <div className="table-wrap"><table><thead><tr><th>Batch ID</th><th>Kaynak sözleşmesi</th><th>Kayıt</th><th>Durum</th><th>Başlangıç</th><th>İşlem</th></tr></thead><tbody>{batches.map((batch) => <tr key={batch.id}><td>{batch.id}</td><td>{batch.source_kind}</td><td>{number(batch.expected_rows)}</td><td><span className={`state-badge ${batch.status.toLowerCase()}`}>{batch.status}</span></td><td>{formatDate(batch.created_at)}</td><td><button className="link-button" type="button" onClick={() => onOpen(batch.id)}>Detay</button></td></tr>)}</tbody></table></div> : <EmptyState text="Henüz operasyon batch’i yok." /> }
function ViewerHistory({ publications, onOpen }: { publications: Publication[]; onOpen: (publication: Publication) => void }) { return publications.length ? <div className="table-wrap"><table><thead><tr><th>Publication</th><th>Kaynak</th><th>Sürüm</th><th>Yayın zamanı</th><th>Durum</th><th>İşlem</th></tr></thead><tbody>{publications.map((publication) => <tr key={publication.id}><td>{publication.id}</td><td>{publication.source_kind}</td><td>{number(publication.version)}</td><td>{formatDate(publication.published_at)}</td><td><span className="state-badge published">Yayınlandı · PUBLISHED</span></td><td><button className="link-button" type="button" onClick={() => onOpen(publication)}>Provenance</button></td></tr>)}</tbody></table></div> : <EmptyState text="Henüz published yayın yok." /> }
function BatchDrawer({ detail, confirmation, activeHead, activePublication, onClose, onRequestPublish, onCancelPublish, onConfirmPublish, publishing }: { detail: BatchDetail; confirmation: boolean; activeHead: PublicationHead | null; activePublication: Publication | null; onClose: () => void; onRequestPublish: () => void; onCancelPublish: () => void; onConfirmPublish: () => void; publishing: boolean }) {
  const reconciliation = detail.reconciliation
  const candidateReady = detail.candidate?.status === 'READY'
  const nextVersion = (activeHead?.version ?? 0) + 1
  return <div className="drawer-shell" role="dialog" aria-modal="true" aria-labelledby="batch-detail-title"><button className="drawer-close" type="button" onClick={onClose} aria-label="Batch detayını kapat">×</button><p className="eyebrow">{confirmation ? 'YAYIN ONAYI' : 'BATCH DETAIL'}</p><h2 id="batch-detail-title">{detail.batch.source_kind} · {detail.batch.id}</h2>{confirmation ? <><div className="drawer-section"><h3>Yayınlanacak kayıt</h3><KeyValue label="Candidate" value={detail.candidate?.id ?? '—'} /><KeyValue label="Batch" value={detail.batch.id} /><KeyValue label="Kaynak sözleşmesi" value={`${detail.contract?.sourceKind ?? detail.batch.source_kind} · v${detail.contract?.version ?? '—'}`} /><KeyValue label="Parsed / Valid" value={reconciliation ? `${number(reconciliation.parsed_rows)} / ${number(reconciliation.valid_rows)}` : '—'} /><KeyValue label="Blocked / Duplicate" value={reconciliation ? `${number(reconciliation.blocked_rows)} / ${number(reconciliation.duplicate_rows)}` : '—'} /><KeyValue label="Reconciliation" value={reconciliation?.status ?? '—'} /></div><div className="drawer-section"><h3>Publication etkisi</h3><KeyValue label="Mevcut aktif publication" value={activePublication ? `${activePublication.id} · v${activePublication.version}` : 'Yok · ilk yayın'} /><KeyValue label="Oluşturulacak yeni version" value={`v${nextVersion}`} /><p className="drawer-confirmation-note">Önceki aktif yayın korunur; yeni publication başarılı onaydan sonra aktif başlığa alınır.</p></div><div className="drawer-actions"><button className="secondary-button" type="button" onClick={onCancelPublish} disabled={publishing}>Geri dön</button><button className="publish-button" type="button" onClick={onConfirmPublish} disabled={publishing || !candidateReady}>{publishing ? 'Yayınlanıyor…' : 'Yayınlamayı onayla'}</button></div></> : <><div className="drawer-section"><h3>Özet</h3><KeyValue label="İş durumu" value={`${statusLabels[statusForBatch(detail.batch)]} · ${detail.batch.status}`} /><KeyValue label="Parsed / Valid" value={reconciliation ? `${number(reconciliation.parsed_rows)} / ${number(reconciliation.valid_rows)}` : '—'} /><KeyValue label="Blocked / Duplicate" value={reconciliation ? `${number(reconciliation.blocked_rows)} / ${number(reconciliation.duplicate_rows)}` : '—'} /><KeyValue label="Reconciliation" value={reconciliation ? reconciliation.status : '—'} /></div><div className="drawer-section"><h3>Kaynak sözleşmesi</h3><KeyValue label="Kaynak" value={detail.contract?.sourceKind ?? detail.batch.source_kind} /><KeyValue label="Version" value={detail.contract?.version ?? '—'} /><KeyValue label="Başlangıç" value={formatDate(detail.batch.created_at)} /></div><ValidationIssueList issues={detail.issues} total={detail.issueTotal} /><div className="drawer-section"><h3>Provenance</h3><code className="provenance">batch_id: {detail.batch.id}<br />source_contract: {detail.batch.source_contract_version_id}<br />storage_evidence: {detail.batch.storage_bucket}/{detail.batch.storage_object_path}</code></div>{candidateReady ? <button className="publish-button" type="button" onClick={onRequestPublish} disabled={publishing}>İncele ve yayınla</button> : null}</>}</div>
}
function ValidationIssueList({ issues, total }: { issues: ValidationIssue[]; total: number }) {
  if (!total) return null
  return <div className="drawer-section"><h3>Doğrulama sorunları ({number(total)})</h3><p>Gösterilen: {number(issues.length)} / {number(total)}</p><div className="validation-issue-list">{issues.map((issue) => <article className="validation-issue" key={issue.id}><strong>Satır {display(issue.detail.source_row_no)} · {issue.code}</strong>{issue.detail.missing_required_fields?.length ? <p>Eksik alanlar: {issue.detail.missing_required_fields.join(', ')}</p> : null}{issue.detail.invalid_control_total_fields?.length ? <p>Geçersiz control alanları: {issue.detail.invalid_control_total_fields.join(', ')}</p> : null}</article>)}</div></div>
}
function PublicationDrawer({ publication, onClose }: { publication: Publication; onClose: () => void }) { return <div className="drawer-shell" role="dialog" aria-modal="true" aria-labelledby="publication-detail-title"><button className="drawer-close" type="button" onClick={onClose} aria-label="Publication detayını kapat">×</button><p className="eyebrow">PUBLISHED PROVENANCE</p><h2 id="publication-detail-title">{publication.source_kind} · v{publication.version}</h2><div className="drawer-section"><KeyValue label="Durum" value="Yayınlandı · PUBLISHED" /><KeyValue label="Scope" value={publication.scope_key} /><KeyValue label="Yayın zamanı" value={formatDate(publication.published_at)} /></div><div className="drawer-section"><h3>Provenance</h3><code className="provenance">publication_id: {publication.id}<br />candidate_id: {publication.candidate_id}<br />source: {publication.source_kind}</code></div></div> }
function KeyValue({ label, value }: { label: string; value: string }) { return <div className="key-value"><span>{label}</span><strong>{value}</strong></div> }
