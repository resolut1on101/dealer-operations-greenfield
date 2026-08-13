import { z } from 'zod'

export const applicationEnvironmentSchema = z.enum(['local', 'dev', 'live'])
export type ApplicationEnvironment = z.infer<typeof applicationEnvironmentSchema>

export const applicationRoleSchema = z.enum(['admin', 'viewer'])
export type ApplicationRole = z.infer<typeof applicationRoleSchema>

export const releaseStateSchema = z.enum(['LIVE_TESTING', 'VERIFIED', 'BLOCKED'])
export type ReleaseState = z.infer<typeof releaseStateSchema>

export const packageIdentifierSchema = z.enum(['00C', '01', '02', '02U', '03'])

export const productCodeSchema = z.string().regex(/^[0-9]+$/)
export type ProductCode = z.infer<typeof productCodeSchema>

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
