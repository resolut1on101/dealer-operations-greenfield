import { z } from 'zod'

export const applicationEnvironmentSchema = z.enum(['local', 'dev', 'live'])
export type ApplicationEnvironment = z.infer<typeof applicationEnvironmentSchema>

export const applicationRoleSchema = z.enum(['admin', 'viewer'])
export type ApplicationRole = z.infer<typeof applicationRoleSchema>

export const releaseStateSchema = z.enum(['LIVE_TESTING', 'VERIFIED', 'BLOCKED'])
export type ReleaseState = z.infer<typeof releaseStateSchema>

export const packageIdentifierSchema = z.literal('00C')
