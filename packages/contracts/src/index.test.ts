import { describe, expect, it } from 'vitest'
import { applicationRoleSchema, importChunkSchema, sourceContractSignatureSchema } from './index'

describe('application role contract', () => {
  it('permits only admin and viewer', () => {
    expect(applicationRoleSchema.parse('admin')).toBe('admin')
    expect(applicationRoleSchema.parse('viewer')).toBe('viewer')
    expect(() => applicationRoleSchema.parse('editor')).toThrow()
  })
})

describe('Package 01 import transport contracts', () => {
  it('requires an exact chunk row count and SHA-256-shaped idempotency key', () => {
    const chunk = {
      batchId: '10000000-0000-4000-8000-000000000001',
      chunkNo: 0,
      rowOffset: 0,
      chunkHash: 'a'.repeat(64),
      rowCount: 1,
      rows: [{ id: 'one' }],
    }
    expect(importChunkSchema.parse(chunk).rowCount).toBe(1)
    expect(() => importChunkSchema.parse({ ...chunk, rowCount: 2 })).toThrow()
  })

  it('keeps source recognition contract-driven rather than filename-driven', () => {
    expect(sourceContractSignatureSchema.parse({
      sourceKind: 'CUSTOMER_MASTER', version: '1', requiredSheet: 'Data',
      requiredHeaders: ['Customer Code'], requiredFields: ['Customer Code'],
      controlTotalFields: {}, publicationMode: 'FULL_REPLACE',
    }).sourceKind).toBe('CUSTOMER_MASTER')
  })
})
