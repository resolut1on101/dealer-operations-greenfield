import type { SourceContractSignature } from '@dealer-operations/contracts'
import { supabase } from './supabase'

export type ImportBatchStatus = 'CREATED' | 'AWAITING_SOURCE_VERIFICATION' | 'STAGING' | 'VALIDATED' | 'RECONCILED' | 'CANDIDATE_READY' | 'PUBLISHING' | 'PUBLISHED' | 'FAILED'
export type Publication = { id: string; candidate_id: string; source_kind: string; scope_key: string; version: number; manifest: Record<string, unknown>; published_by: string; published_at: string; superseded_at: string | null }
export type PublicationHead = { source_kind: string; scope_key: string; active_publication_id: string; version: number; updated_at: string }
export type SourceContract = SourceContractSignature & { id: string; is_active: boolean; retired_at: string | null }
export type ImportBatch = { id: string; source_contract_version_id: string; source_kind: string; scope_key: string; source_sheet: string; source_headers: string[]; storage_bucket: string; storage_object_path: string; declared_file_hash: string; verified_file_hash: string | null; file_size_bytes: number; expected_rows: number; expected_chunks: number; received_chunks: number; staged_rows: number; expected_control_totals: Record<string, string | number>; status: ImportBatchStatus; source_verified_at: string | null; validation_run_id: string | null; reconciliation_id: string | null; published_publication_id: string | null; created_at: string; updated_at: string; completed_at: string | null }
export type ValidationRun = { id: string; valid_rows: number; excluded_rows: number; blocked_rows: number; duplicate_rows: number; status: string }
export type ValidationIssue = { id: number; staging_row_id: number | null; severity: string; code: string; detail: { source_row_no?: number; missing_required_fields?: string[]; invalid_control_total_fields?: string[] } }
export type Reconciliation = { id: string; parsed_rows: number; valid_rows: number; excluded_rows: number; blocked_rows: number; duplicate_rows: number; expected_control_totals: Record<string, unknown>; actual_control_totals: Record<string, unknown>; status: 'MATCHED' | 'MISMATCHED' }
export type Candidate = { id: string; batch_id: string; status: 'READY' | 'PUBLISHED' | 'SUPERSEDED' | 'FAILED'; manifest: Record<string, unknown>; created_at: string; published_at: string | null }
export type BatchDetail = { batch: ImportBatch; contract: SourceContract | null; validation: ValidationRun | null; issues: ValidationIssue[]; issueTotal: number; reconciliation: Reconciliation | null; candidate: Candidate | null }

const VALIDATION_ISSUE_PAGE_SIZE = 500

async function listValidationIssues(
  api: ReturnType<typeof client>,
  validationRunId: string,
): Promise<{ issues: ValidationIssue[]; total: number }> {
  const issues: ValidationIssue[] = []
  let from = 0
  let exactTotal: number | null = null

  while (true) {
    const { data, error, count } = await api
      .from('validation_issues')
      .select(
        'id,staging_row_id,severity,code,detail',
        { count: 'exact' },
      )
      .eq('validation_run_id', validationRunId)
      .order('id', { ascending: true })
      .range(from, from + VALIDATION_ISSUE_PAGE_SIZE - 1)

    if (error) throw error

    if (exactTotal === null && count !== null) {
      exactTotal = count
    }

    const page = (data ?? []) as unknown as ValidationIssue[]
    issues.push(...page)

    if (
      page.length < VALIDATION_ISSUE_PAGE_SIZE ||
      (exactTotal !== null && issues.length >= exactTotal)
    ) {
      break
    }

    from += VALIDATION_ISSUE_PAGE_SIZE
  }

  return {
    issues,
    total: exactTotal ?? issues.length,
  }
}

function mapSourceContract(row: Record<string, unknown>): SourceContract {
  return {
    id: String(row.id),
    sourceKind: String(row.source_kind),
    version: String(row.version),
    requiredSheet: String(row.required_sheet),
    requiredHeaders: (row.required_headers ?? []) as string[],
    requiredFields: (row.required_fields ?? []) as string[],
    controlTotalFields: (row.control_total_fields ?? {}) as Record<string, string>,
    controlTotalScales: (row.control_total_scales ?? {}) as Record<string, number>,
    publicationMode: row.publication_mode as SourceContract['publicationMode'],
    is_active: Boolean(row.is_active),
    retired_at: (row.retired_at as string | null | undefined) ?? null,
  }
}

function client() {
  if (!supabase) throw new Error('Supabase bağlantısı yapılandırılmamış.')
  return supabase
}

export async function listSourceContracts() {
  const { data, error } = await client().from('source_contract_versions').select('*').eq('is_active', true).order('source_kind')
  if (error) throw error
  return (data ?? []).map((row) => mapSourceContract(row as Record<string, unknown>))
}

export async function listAdminBatches() {
  const { data, error } = await client().from('import_batches').select('*').order('created_at', { ascending: false }).limit(48)
  if (error) throw error
  return (data ?? []) as unknown as ImportBatch[]
}

export async function listPublishedHistory() {
  const { data, error } = await client().from('publications').select('*').order('published_at', { ascending: false }).limit(48)
  if (error) throw error
  return (data ?? []) as unknown as Publication[]
}

export async function listPublicationHeads() {
  const { data, error } = await client().from('publication_heads').select('*').order('source_kind')
  if (error) throw error
  return (data ?? []) as unknown as PublicationHead[]
}

export async function getAdminBatchDetail(batchId: string): Promise<BatchDetail> {
  const api = client()
  const [{ data: batch, error: batchError }, { data: validation }, { data: reconciliation }, { data: candidate }] = await Promise.all([
    api.from('import_batches').select('*').eq('id', batchId).single(),
    api.from('validation_runs').select('*').eq('batch_id', batchId).maybeSingle(),
    api.from('import_reconciliations').select('*').eq('batch_id', batchId).maybeSingle(),
    api.from('candidate_publications').select('*').eq('batch_id', batchId).maybeSingle(),
  ])
  if (batchError) throw batchError
  const { data: contract } = await api.from('source_contract_versions').select('*').eq('id', (batch as ImportBatch).source_contract_version_id).maybeSingle()
  const validationRun = validation as unknown as ValidationRun | null
  const issueResult = validationRun
    ? await listValidationIssues(api, validationRun.id)
    : { issues: [], total: 0 }
  return {
    batch: batch as ImportBatch,
    contract: contract
      ? mapSourceContract(contract as Record<string, unknown>)
      : null,
    validation: validationRun,
    issues: issueResult.issues,
    issueTotal: issueResult.total,
    reconciliation: reconciliation as unknown as Reconciliation | null,
    candidate: candidate as unknown as Candidate | null,
  }
}

export async function createImportBatch(input: { contractId: string; scopeKey: string; sourceSheet: string; sourceHeaders: string[]; fileHash: string; fileSize: number; expectedRows: number; expectedChunks: number; expectedControlTotals: Record<string, number | string> }) {
  const { data, error } = await client().rpc('create_import_batch', {
    p_source_contract_version_id: input.contractId,
    p_scope_key: input.scopeKey,
    p_source_sheet: input.sourceSheet,
    p_source_headers: input.sourceHeaders,
    p_file_hash: input.fileHash,
    p_file_size_bytes: input.fileSize,
    p_expected_rows: input.expectedRows,
    p_expected_chunks: input.expectedChunks,
    p_expected_control_totals: input.expectedControlTotals,
  })
  if (error) throw error
  return data as unknown as ImportBatch
}

export async function uploadSource(batch: ImportBatch, file: File) {
  const { error } = await client().storage.from(batch.storage_bucket).upload(batch.storage_object_path, file, { contentType: file.type || 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet', upsert: false })
  if (error) throw error
}

export async function sourceObjectExists(batch: ImportBatch) {
  const separator = batch.storage_object_path.lastIndexOf('/')
  const folder = separator >= 0 ? batch.storage_object_path.slice(0, separator) : ''
  const name = separator >= 0 ? batch.storage_object_path.slice(separator + 1) : batch.storage_object_path
  const { data, error } = await client().storage.from(batch.storage_bucket).list(folder, { limit: 100, search: name })
  if (error) throw error
  return (data ?? []).some((entry) => entry.name === name)
}

export async function verifySource(batchId: string) {
  const { error } = await client().functions.invoke('verify-import-source', { body: { batchId } })
  if (error) throw error
}

export async function stageChunk(chunk: { batchId: string; chunkNo: number; rowOffset: number; chunkHash: string; rowCount: number; rows: Record<string, unknown>[] }) {
  const { error } = await client().rpc('stage_import_chunk', { p_batch_id: chunk.batchId, p_chunk_no: chunk.chunkNo, p_row_offset: chunk.rowOffset, p_chunk_hash: chunk.chunkHash, p_row_count: chunk.rowCount, p_rows: chunk.rows })
  if (error) throw error
}

export async function validateBatch(batchId: string) {
  const { error } = await client().rpc('validate_import_batch', { p_batch_id: batchId })
  if (error) throw error
}

export async function reconcileBatch(batchId: string) {
  const { error } = await client().rpc('reconcile_import_batch', { p_batch_id: batchId })
  if (error) throw error
}

export async function createCandidate(batchId: string, manifest: Record<string, unknown>) {
  const { data, error } = await client().rpc('create_candidate_publication', { p_batch_id: batchId, p_manifest: manifest })
  if (error) throw error
  return data as string
}

export async function publishCandidate(candidateId: string, expectedActivePublicationId: string | null) {
  const { data, error } = await client().rpc('publish_candidate', { p_candidate_id: candidateId, p_expected_active_publication_id: expectedActivePublicationId })
  if (error) throw error
  return data as string
}
