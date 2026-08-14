import { describe, expect, it } from 'vitest'
import { applicationRoleSchema, customerMasterRowSchema, customerStatusSchema, importChunkSchema, productBusinessRowSchema, productCanonicalMappingSchema, productDomainFreshnessSchema, productDomainFreshnessStateSchema, productDomainSummarySchema, productResolutionStateSchema, roundCanonicalQuantityForDisplay, sourceContractSignatureSchema } from './index'

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

describe('Package 03 canonical product normalization', () => {
  it('keeps canonical factors exact and makes rounding presentation-only', () => {
    const split = productCanonicalMappingSchema.parse({
      scopeKey: '1237', referenceVersion: 'paket-51fb373c-v1',
      rawProductCode: '154525', canonicalProductCode: '150021',
      canonicalQuantityNumerator: 1, canonicalQuantityDenominator: 2, normalizationPolicy: 'STANDARD',
    })
    expect(split.canonicalProductCode).toBe('150021')
    const exact = 10 + split.canonicalQuantityNumerator / split.canonicalQuantityDenominator + 0.25
    expect(exact).toBe(10.75)
    expect(roundCanonicalQuantityForDisplay(exact)).toBe(11)
    expect(exact * 12).toBe(129)
  })

  it('supports the opposite high-alcohol canonicalization direction', () => {
    const highAlcoholCase = productCanonicalMappingSchema.parse({
      scopeKey: '1237', referenceVersion: 'paket-51fb373c-v1',
      rawProductCode: '152224', canonicalProductCode: '152315',
      canonicalQuantityNumerator: 24, canonicalQuantityDenominator: 1, normalizationPolicy: 'HIGH_ALCOHOL',
    })
    expect(highAlcoholCase.canonicalProductCode).toBe('152315')
    expect(highAlcoholCase.canonicalQuantityNumerator / highAlcoholCase.canonicalQuantityDenominator).toBe(24)
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

  it('enforces product domain freshness state vocabulary', () => {
    expect(productDomainFreshnessStateSchema.parse('FRESH')).toBe('FRESH')
    expect(productDomainFreshnessStateSchema.parse('STALE')).toBe('STALE')
    expect(productDomainFreshnessStateSchema.parse('BLOCKED')).toBe('BLOCKED')
    expect(productDomainFreshnessStateSchema.parse('PENDING_SOURCES')).toBe('PENDING_SOURCES')
    expect(() => productDomainFreshnessStateSchema.parse('OUTDATED')).toThrow()
  })

  it('validates viewer-safe product freshness without exposing internal run ids', () => {
    const freshness = productDomainFreshnessSchema.parse({
      scopeKey: '1237', freshnessState: 'FRESH', freshnessError: null, isFresh: true,
      staleSince: null, lastAttemptedAt: '2026-08-14T00:00:00.000Z',
    })
    expect(freshness.freshnessState).toBe('FRESH')
    expect(freshness.isFresh).toBe(true)
    expect('activeRunId' in freshness).toBe(false)
  })

  it('validates the accepted product domain summary shape independently from freshness state', () => {
    const summary = productDomainSummarySchema.parse({
      scopeKey: '1237',
      variantCount: 10, conversionObservationCount: 5, conversionProductCount: 8, conversionComponentCount: 3,
      directedEdgeCount: 4, familyCount: 2, productNameResolved: 10, productNamePartial: 0, productNameBlocked: 0,
      familyResolved: 10, familyPartial: 0, familyBlocked: 0, familyResolutionCoverage: 1.0,
      quantityUomResolved: 10, quantityUomPartial: 0, quantityUomBlocked: 0,
      lpuResolved: 10, lpuPartial: 0, lpuBlocked: 0, litreResolutionCoverage: 1.0,
      lpuSellout: 8, lpuKa: 2, lpuGraph: 0, lpuCrossSourceVerified: 8, lpuSelloutVerified: 0, lpuKaVerified: 2,
      lpuDerivedPending: 0, lpuMissing: 0, lpuCrossSourceCompared: 8, lpuSourceVarianceNonzero: 0,
      volumeTrackedTrue: 10, volumeTrackedUnknown: 0,
    })
    expect(summary.variantCount).toBe(10)
  })
})
