import { z } from 'zod'

export const applicationEnvironmentSchema = z.enum(['local', 'dev', 'live'])
export type ApplicationEnvironment = z.infer<typeof applicationEnvironmentSchema>

export const applicationRoleSchema = z.enum(['admin', 'viewer'])
export type ApplicationRole = z.infer<typeof applicationRoleSchema>

export const releaseStateSchema = z.enum(['LIVE_TESTING', 'VERIFIED', 'BLOCKED'])
export type ReleaseState = z.infer<typeof releaseStateSchema>

export const packageIdentifierSchema = z.enum(['00C', '01'])

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
  publicationMode: importPublicationModeSchema,
})
export type SourceContractSignature = z.infer<typeof sourceContractSignatureSchema>
