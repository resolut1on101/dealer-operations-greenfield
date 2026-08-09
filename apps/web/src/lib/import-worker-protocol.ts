import type { ImportChunk } from '@dealer-operations/contracts'

export type ParsedImportRow = Record<string, unknown>

export type ImportWorkerRequest = {
  type: 'BUILD_CHUNKS'
  batchId: string
  rows: ParsedImportRow[]
  chunkSize?: number
}

export type ImportWorkerResponse =
  | { type: 'CHUNK'; chunk: ImportChunk }
  | { type: 'COMPLETE'; rowCount: number; chunkCount: number }
  | { type: 'ERROR'; message: string }

export const DEFAULT_IMPORT_CHUNK_SIZE = 1000
