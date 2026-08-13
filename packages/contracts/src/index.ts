import { z } from 'zod'

export const applicationEnvironmentSchema = z.enum(['local', 'dev', 'live'])
export type ApplicationEnvironment = z.infer<typeof applicationEnvironmentSchema>

export const applicationRoleSchema = z.enum(['admin', 'viewer'])
export type ApplicationRole = z.infer<typeof applicationRoleSchema>

export const releaseStateSchema = z.enum(['LIVE_TESTING', 'VERIFIED', 'BLOCKED'])
export type ReleaseState = z.infer<typeof releaseStateSchema>

export const packageIdentifierSchema = z.enum(['00C', '01', '02', '02U'])

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
