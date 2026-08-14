import { z } from 'zod'

export const applicationEnvironmentSchema = z.enum(['local', 'dev', 'live'])
export type ApplicationEnvironment = z.infer<typeof applicationEnvironmentSchema>

export const applicationRoleSchema = z.enum(['admin', 'viewer'])
export type ApplicationRole = z.infer<typeof applicationRoleSchema>

export const releaseStateSchema = z.enum(['LIVE_TESTING', 'VERIFIED', 'BLOCKED'])
export type ReleaseState = z.infer<typeof releaseStateSchema>

export const packageIdentifierSchema = z.enum(['00C', '01', '02', '02U', '03', '03A'])

export const productCodeSchema = z.string().regex(/^[0-9]+$/)
export type ProductCode = z.infer<typeof productCodeSchema>

export const productCanonicalizationPolicySchema = z.enum(['STANDARD', 'HIGH_ALCOHOL', 'IDENTITY'])
export type ProductCanonicalizationPolicy = z.infer<typeof productCanonicalizationPolicySchema>

export const productCanonicalMappingSchema = z.object({
  scopeKey: z.string().min(1),
  referenceVersion: z.string().min(1),
  rawProductCode: productCodeSchema,
  canonicalProductCode: productCodeSchema,
  canonicalQuantityNumerator: z.number().int().positive(),
  canonicalQuantityDenominator: z.number().int().positive(),
  normalizationPolicy: productCanonicalizationPolicySchema,
})
export type ProductCanonicalMapping = z.infer<typeof productCanonicalMappingSchema>

// Presentation-only helper. The exact canonical quantity must remain the calculation input.
export function roundCanonicalQuantityForDisplay(exactCanonicalQuantity: number) {
  if (!Number.isFinite(exactCanonicalQuantity)) throw new Error('Canonical quantity must be finite')
  return Math.round(exactCanonicalQuantity)
}

export const productResolutionStateSchema = z.enum(['RESOLVED', 'PARTIAL', 'BLOCKED'])
export type ProductResolutionState = z.infer<typeof productResolutionStateSchema>

export const productLpuSourceSchema = z.enum(['SELLOUT', 'KA_DELIVERY', 'CONVERSION_GRAPH', 'APPROVED_MANUAL'])
export type ProductLpuSource = z.infer<typeof productLpuSourceSchema>

export const productFamilySourceSchema = z.enum(['SELLOUT', 'CONVERSION_GRAPH', 'APPROVED_MANUAL'])
export type ProductFamilySource = z.infer<typeof productFamilySourceSchema>

export const productLpuVerificationStateSchema = z.enum([
  'sellout_verified', 'ka_verified', 'cross_source_verified', 'unit_inconsistent',
  'derived_pending', 'manual_approved', 'non_volume', 'missing',
])
export type ProductLpuVerificationState = z.infer<typeof productLpuVerificationStateSchema>

export const productQuantityUomSourceSchema = z.enum(['PRODUCT_CONVERSION', 'APPROVED_MANUAL'])
export type ProductQuantityUomSource = z.infer<typeof productQuantityUomSourceSchema>

export const productBusinessRowSchema = z.object({
  scopeKey: z.string().min(1),
  productCode: productCodeSchema,
  productName: z.string().nullable(),
  productNameResolutionState: productResolutionStateSchema,
  family: z.string().nullable(),
  familyResolutionState: productResolutionStateSchema,
  familySource: productFamilySourceSchema.nullable(),
  quantityUom: z.string().min(1).nullable(),
  quantityUomResolutionState: productResolutionStateSchema,
  quantityUomSource: productQuantityUomSourceSchema.nullable(),
  unitsPerCase: z.number().positive().nullable(),
  unitVolumeMl: z.number().positive().nullable(),
  canonicalStockVariantCode: productCodeSchema.nullable(),
  replenishmentVariantCode: productCodeSchema.nullable(),
  volumeTracked: z.boolean().nullable(),
  selloutLpuCandidate: z.number().positive().nullable(),
  kaLpuCandidate: z.number().positive().nullable(),
  packageLpuCandidate: z.number().positive().nullable(),
  lpu: z.number().positive().nullable(),
  lpuResolutionState: productResolutionStateSchema,
  lpuSource: productLpuSourceSchema.nullable(),
  lpuVerificationState: productLpuVerificationStateSchema,
  lpuSourceVariance: z.number().nonnegative().nullable(),
  lpuSourceVarianceRatio: z.number().nonnegative().nullable(),
  conversionDeltaLpu: z.number().nullable(),
  conversionComponentKey: z.string().nullable(),
  hasConversion: z.boolean(),
}).superRefine((row, context) => {
  if (row.productNameResolutionState === 'RESOLVED' && !row.productName) {
    context.addIssue({ code: 'custom', message: 'resolved product name requires productName', path: ['productName'] })
  }
  if (row.productNameResolutionState !== 'RESOLVED' && row.productName !== null) {
    context.addIssue({ code: 'custom', message: 'unresolved product name must remain null', path: ['productName'] })
  }
  if (row.familyResolutionState === 'RESOLVED' && (!row.family || !row.familySource)) {
    context.addIssue({ code: 'custom', message: 'resolved family requires family and familySource', path: ['family'] })
  }
  if (row.familyResolutionState !== 'RESOLVED' && (row.family !== null || row.familySource !== null)) {
    context.addIssue({ code: 'custom', message: 'unresolved family and familySource must remain null', path: ['family'] })
  }
  if (row.quantityUomResolutionState === 'RESOLVED' && (!row.quantityUom || !row.quantityUomSource)) {
    context.addIssue({ code: 'custom', message: 'resolved quantity UOM requires quantityUom and quantityUomSource', path: ['quantityUom'] })
  }
  if (row.quantityUomResolutionState !== 'RESOLVED' && (row.quantityUom !== null || row.quantityUomSource !== null)) {
    context.addIssue({ code: 'custom', message: 'unresolved quantity UOM and source must remain null', path: ['quantityUom'] })
  }
  if (row.lpuResolutionState === 'RESOLVED' && (row.lpu === null || !row.lpuSource)) {
    context.addIssue({ code: 'custom', message: 'resolved LPU requires a positive value and lpuSource', path: ['lpu'] })
  }
  if (row.lpuResolutionState === 'RESOLVED' && ['missing', 'unit_inconsistent', 'non_volume'].includes(row.lpuVerificationState)) {
    context.addIssue({ code: 'custom', message: 'resolved LPU requires a resolved verification state', path: ['lpuVerificationState'] })
  }
  if (row.lpuResolutionState !== 'RESOLVED' && row.lpu !== null) {
    context.addIssue({ code: 'custom', message: 'unresolved LPU must remain null', path: ['lpu'] })
  }
  if (row.lpuResolutionState === 'PARTIAL' && !['missing', 'non_volume'].includes(row.lpuVerificationState)) {
    context.addIssue({ code: 'custom', message: 'partial LPU must be missing or explicitly non-volume', path: ['lpuVerificationState'] })
  }
  if (row.lpuResolutionState === 'BLOCKED' && row.lpuVerificationState !== 'unit_inconsistent') {
    context.addIssue({ code: 'custom', message: 'blocked LPU requires unit_inconsistent verification state', path: ['lpuVerificationState'] })
  }
  if (row.volumeTracked === false && (row.lpu !== null || row.lpuVerificationState !== 'non_volume')) {
    context.addIssue({ code: 'custom', message: 'non-volume variants must not expose LPU', path: ['volumeTracked'] })
  }
})
export type ProductBusinessRow = z.infer<typeof productBusinessRowSchema>

export const productDomainFreshnessStateSchema = z.enum(['FRESH', 'STALE', 'BLOCKED', 'PENDING_SOURCES'])
export type ProductDomainFreshnessState = z.infer<typeof productDomainFreshnessStateSchema>

export const productDomainFreshnessSchema = z.object({
  scopeKey: z.string().min(1),
  freshnessState: productDomainFreshnessStateSchema,
  freshnessError: z.string().nullable(),
  isFresh: z.boolean(),
  staleSince: z.string().datetime().nullable(),
  lastAttemptedAt: z.string().datetime().nullable(),
})
export type ProductDomainFreshness = z.infer<typeof productDomainFreshnessSchema>


export const warehouseStockLitreResolutionStateSchema = z.enum(['RESOLVED', 'PARTIAL'])
export type WarehouseStockLitreResolutionState = z.infer<typeof warehouseStockLitreResolutionStateSchema>

export const warehouseStockBusinessRowSchema = z.object({
  scopeKey: z.string().min(1),
  productCode: productCodeSchema,
  productName: z.string().min(1).nullable(),
  exactAvailableQuantity: z.number().finite(),
  lpu: z.number().positive().nullable(),
  availableLitres: z.number().finite().nullable(),
  litreResolutionState: warehouseStockLitreResolutionStateSchema,
  sourcePublishedAt: z.string().datetime(),
}).superRefine((row, context) => {
  if (row.litreResolutionState === 'RESOLVED' && (row.lpu === null || row.availableLitres === null)) {
    context.addIssue({ code: 'custom', message: 'resolved warehouse stock litres require LPU and litres', path: ['availableLitres'] })
  }
  if (row.litreResolutionState === 'PARTIAL' && (row.lpu !== null || row.availableLitres !== null)) {
    context.addIssue({ code: 'custom', message: 'partial warehouse stock litres must remain null', path: ['availableLitres'] })
  }
})
export type WarehouseStockBusinessRow = z.infer<typeof warehouseStockBusinessRowSchema>

export const warehouseStockSummarySchema = z.object({
  scopeKey: z.string().min(1),
  businessRowCount: z.number().int().nonnegative(),
  litreResolvedCount: z.number().int().nonnegative(),
  litrePartialCount: z.number().int().nonnegative(),
  sourcePublishedAt: z.string().datetime(),
})
export type WarehouseStockSummary = z.infer<typeof warehouseStockSummarySchema>

export const productDomainSummarySchema = z.object({
  scopeKey: z.string().min(1),
  variantCount: z.number().int().nonnegative(),
  conversionObservationCount: z.number().int().nonnegative(),
  conversionProductCount: z.number().int().nonnegative(),
  conversionComponentCount: z.number().int().nonnegative(),
  directedEdgeCount: z.number().int().nonnegative(),
  familyCount: z.number().int().nonnegative(),
  productNameResolved: z.number().int().nonnegative(),
  productNamePartial: z.number().int().nonnegative(),
  productNameBlocked: z.number().int().nonnegative(),
  familyResolved: z.number().int().nonnegative(),
  familyPartial: z.number().int().nonnegative(),
  familyBlocked: z.number().int().nonnegative(),
  familyResolutionCoverage: z.number().nullable(),
  quantityUomResolved: z.number().int().nonnegative(),
  quantityUomPartial: z.number().int().nonnegative(),
  quantityUomBlocked: z.number().int().nonnegative(),
  lpuResolved: z.number().int().nonnegative(),
  lpuPartial: z.number().int().nonnegative(),
  lpuBlocked: z.number().int().nonnegative(),
  litreResolutionCoverage: z.number().nullable(),
  lpuSellout: z.number().int().nonnegative(),
  lpuKa: z.number().int().nonnegative(),
  lpuGraph: z.number().int().nonnegative(),
  lpuCrossSourceVerified: z.number().int().nonnegative(),
  lpuSelloutVerified: z.number().int().nonnegative(),
  lpuKaVerified: z.number().int().nonnegative(),
  lpuDerivedPending: z.number().int().nonnegative(),
  lpuMissing: z.number().int().nonnegative(),
  lpuCrossSourceCompared: z.number().int().nonnegative(),
  lpuSourceVarianceNonzero: z.number().int().nonnegative(),
  volumeTrackedTrue: z.number().int().nonnegative(),
  volumeTrackedUnknown: z.number().int().nonnegative(),
})
export type ProductDomainSummary = z.infer<typeof productDomainSummarySchema>

export const customerStatusSchema = z.enum(['ACTIVE', 'PASSIVE', 'CANCELLED', 'UNKNOWN'])
export type CustomerStatus = z.infer<typeof customerStatusSchema>
export const customerChannelSchema = z.enum(['OPEN', 'CLOSED', 'UNCLASSIFIED'])
export type CustomerChannel = z.infer<typeof customerChannelSchema>
export const customerMasterRowSchema = z.object({
  source_row_no: z.number().int().positive(),
  customer_id: z.string().regex(/^500[0-9]+$/),
  customer_name: z.string().nullable().optional(),
  trade_name: z.string().nullable().optional(),
  raw_status: z.string().nullable().optional(),
  raw_channel: z.string().nullable().optional(),
  segment: z.string().nullable().optional(),
  raw_representative: z.string().nullable().optional(),
  raw_ssm: z.string().nullable().optional(),
  raw_payload: z.record(z.string(), z.unknown()),
})
export type CustomerMasterRow = z.infer<typeof customerMasterRowSchema>

// Package 01 is intentionally domain-neutral. Domain packages supply contract instances,
// parsers and canonical adapters without replacing this transport/publication contract.
export const importPublicationModeSchema = z.enum(['FULL_REPLACE', 'APPEND_ONLY', 'UPSERT_VERSIONED'])
export type ImportPublicationMode = z.infer<typeof importPublicationModeSchema>

export const importChunkSchema = z.object({
  batchId: z.string().uuid(),
  chunkNo: z.number().int().nonnegative(),
  rowOffset: z.number().int().nonnegative(),
  chunkHash: z.string().regex(/^[a-f0-9]{64}$/),
  rowCount: z.number().int().nonnegative(),
  rows: z.array(z.record(z.string(), z.unknown())),
}).superRefine((chunk, context) => {
  if (chunk.rows.length !== chunk.rowCount) {
    context.addIssue({ code: 'custom', message: 'rowCount must equal rows.length', path: ['rowCount'] })
  }
})
export type ImportChunk = z.infer<typeof importChunkSchema>

export const sourceContractSignatureSchema = z.object({
  sourceKind: z.string().regex(/^[A-Z][A-Z0-9_]{1,63}$/),
  version: z.string().min(1),
  requiredSheet: z.string().min(1),
  requiredHeaders: z.array(z.string().min(1)),
  requiredFields: z.array(z.string().min(1)),
  controlTotalFields: z.record(z.string(), z.string()),
  controlTotalScales: z.record(z.string(), z.number().int().min(0).max(18)),
  publicationMode: importPublicationModeSchema,
})
export type SourceContractSignature = z.infer<typeof sourceContractSignatureSchema>
