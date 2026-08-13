import { describe, expect, it } from 'vitest'
import { applicationRoleSchema, customerMasterRowSchema, customerStatusSchema, importChunkSchema, productBusinessRowSchema, productResolutionStateSchema, sourceContractSignatureSchema } from './index'

describe('application role contract', () => {
  it('permits only admin and viewer', () => {
    expect(applicationRoleSchema.parse('admin')).toBe('admin')
    expect(applicationRoleSchema.parse('viewer')).toBe('viewer')
    expect(() => applicationRoleSchema.parse('editor')).toThrow()
  })
})

describe('Package 02 customer contracts', () => {
  it('preserves exact 500-prefixed customer text identifiers', () => {
    expect(customerMasterRowSchema.parse({ source_row_no: 1, customer_id: '500001', raw_payload: {} }).customer_id).toBe('500001')
    expect(() => customerMasterRowSchema.parse({ source_row_no: 1, customer_id: '5001.0', raw_payload: {} })).toThrow()
  })

  it('keeps the approved status vocabulary', () => {
    expect(customerStatusSchema.parse('ACTIVE')).toBe('ACTIVE')
    expect(() => customerStatusSchema.parse('DELETED')).toThrow()
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
      controlTotalFields: {}, controlTotalScales: {}, publicationMode: 'FULL_REPLACE',
    }).sourceKind).toBe('CUSTOMER_MASTER')
  })
})

describe('Package 03 product contracts', () => {
  it('preserves exact text product identity and never treats missing LPU as zero', () => {
    const row = productBusinessRowSchema.parse({
      scopeKey: '1237', productCode: '150487', productName: null, productNameResolutionState: 'PARTIAL', family: null,
      familyResolutionState: 'PARTIAL', familySource: null,
      quantityUom: null, quantityUomResolutionState: 'PARTIAL', quantityUomSource: null,
      unitsPerCase: null, unitVolumeMl: null, canonicalStockVariantCode: null, replenishmentVariantCode: null, volumeTracked: null,
      selloutLpuCandidate: null, kaLpuCandidate: null, packageLpuCandidate: null,
      lpu: null, lpuResolutionState: 'PARTIAL', lpuSource: null, lpuVerificationState: 'missing',
      lpuSourceVariance: null, lpuSourceVarianceRatio: null, conversionDeltaLpu: null,
      conversionComponentKey: '150487', hasConversion: true,
    })
    expect(row.productCode).toBe('150487')
    expect(row.lpu).toBeNull()
    expect(() => productBusinessRowSchema.parse({ ...row, lpu: 0, lpuResolutionState: 'RESOLVED' })).toThrow()
    expect(() => productBusinessRowSchema.parse({ ...row, lpu: 1, lpuResolutionState: 'PARTIAL', lpuSource: 'SELLOUT' })).toThrow()
    expect(() => productBusinessRowSchema.parse({ ...row, family: 'Efes Pilsen', familyResolutionState: 'PARTIAL' })).toThrow()
    expect(() => productBusinessRowSchema.parse({ ...row, familySource: 'SELLOUT', familyResolutionState: 'PARTIAL' })).toThrow()
    expect(() => productBusinessRowSchema.parse({ ...row, quantityUomSource: 'PRODUCT_CONVERSION', quantityUomResolutionState: 'PARTIAL' })).toThrow()
    expect(() => productBusinessRowSchema.parse({ ...row, productName: 'Known', productNameResolutionState: 'PARTIAL' })).toThrow()
    expect(() => productBusinessRowSchema.parse({ ...row, productNameResolutionState: 'RESOLVED' })).toThrow()
  })

  it('keeps explicit product missing/conflict states', () => {
    expect(productResolutionStateSchema.parse('RESOLVED')).toBe('RESOLVED')
    expect(productResolutionStateSchema.parse('PARTIAL')).toBe('PARTIAL')
    expect(productResolutionStateSchema.parse('BLOCKED')).toBe('BLOCKED')
  })

  it('keeps quantity-UOM and LPU verification semantics explicit', () => {
    const resolved = productBusinessRowSchema.parse({
      scopeKey: '1237', productCode: '151428', productName: 'Known', productNameResolutionState: 'RESOLVED',
      family: 'Family', familyResolutionState: 'RESOLVED', familySource: 'SELLOUT',
      quantityUom: 'KL', quantityUomResolutionState: 'RESOLVED', quantityUomSource: 'PRODUCT_CONVERSION',
      unitsPerCase: null, unitVolumeMl: null, canonicalStockVariantCode: null, replenishmentVariantCode: null, volumeTracked: true,
      selloutLpuCandidate: 5.688, kaLpuCandidate: 5.68898, packageLpuCandidate: 5.688,
      lpu: 5.688, lpuResolutionState: 'RESOLVED', lpuSource: 'SELLOUT', lpuVerificationState: 'sellout_verified',
      lpuSourceVariance: 0.00098, lpuSourceVarianceRatio: 0.0001723, conversionDeltaLpu: 0,
      conversionComponentKey: '151428', hasConversion: true,
    })
    expect(resolved.quantityUom).toBe('KL')
    expect(resolved.lpuVerificationState).toBe('sellout_verified')
    expect(() => productBusinessRowSchema.parse({ ...resolved, quantityUom: null })).toThrow()
    expect(() => productBusinessRowSchema.parse({ ...resolved, lpu: null, lpuVerificationState: 'missing' })).toThrow()
  })

})
