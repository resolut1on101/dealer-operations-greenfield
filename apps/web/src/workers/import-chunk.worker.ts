import type { ImportChunk } from '@dealer-operations/contracts'
import {
  DEFAULT_IMPORT_CHUNK_SIZE,
  type ImportWorkerRequest,
  type ImportWorkerResponse,
  type ParsedImportRow,
} from '../lib/import-worker-protocol'

function canonicalJson(value: unknown): string {
  if (Array.isArray(value)) return `[${value.map(canonicalJson).join(',')}]`
  if (value !== null && typeof value === 'object') {
    const object = value as Record<string, unknown>
    const compareUtf8 = (left: string, right: string) => {
      const leftBytes = new TextEncoder().encode(left)
      const rightBytes = new TextEncoder().encode(right)
      for (let index = 0; index < Math.min(leftBytes.length, rightBytes.length); index += 1) {
        if (leftBytes[index] !== rightBytes[index]) return leftBytes[index] - rightBytes[index]
      }
      return leftBytes.length - rightBytes.length
    }
    return `{${Object.keys(object).sort(compareUtf8).map((key) => `${JSON.stringify(key)}:${canonicalJson(object[key])}`).join(',')}}`
  }
  return JSON.stringify(value) ?? 'null'
}

async function sha256(value: string): Promise<string> {
  const buffer = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return Array.from(new Uint8Array(buffer), (byte) => byte.toString(16).padStart(2, '0')).join('')
}

async function buildChunk(batchId: string, chunkNo: number, rowOffset: number, rows: ParsedImportRow[]): Promise<ImportChunk> {
  return {
    batchId,
    chunkNo,
    rowOffset,
    chunkHash: await sha256(canonicalJson(rows)),
    rowCount: rows.length,
    rows,
  }
}

self.onmessage = (event: MessageEvent<ImportWorkerRequest>) => {
  void (async () => {
    try {
      if (event.data.type !== 'BUILD_CHUNKS') return
      const chunkSize = event.data.chunkSize ?? DEFAULT_IMPORT_CHUNK_SIZE
      if (!Number.isInteger(chunkSize) || chunkSize < 1 || chunkSize > 5000) {
        throw new Error('Chunk size must be an integer from 1 to 5000.')
      }
      let chunkNo = 0
      for (let offset = 0; offset < event.data.rows.length; offset += chunkSize) {
        const chunk = await buildChunk(event.data.batchId, chunkNo, offset, event.data.rows.slice(offset, offset + chunkSize))
        self.postMessage({ type: 'CHUNK', chunk } satisfies ImportWorkerResponse)
        chunkNo += 1
      }
      self.postMessage({ type: 'COMPLETE', rowCount: event.data.rows.length, chunkCount: chunkNo } satisfies ImportWorkerResponse)
    } catch (error) {
      self.postMessage({ type: 'ERROR', message: error instanceof Error ? error.message : 'Unknown import worker error.' } satisfies ImportWorkerResponse)
    }
  })()
}
