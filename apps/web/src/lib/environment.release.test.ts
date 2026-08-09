import { describe, expect, it } from 'vitest'
import { applicationEnvironmentSchema, packageIdentifierSchema, releaseStateSchema } from '@dealer-operations/contracts'

describe('Package 00C release metadata contract', () => {
  it('permits only observable Package 00C release states', () => {
    expect(releaseStateSchema.parse('LIVE_TESTING')).toBe('LIVE_TESTING')
    expect(releaseStateSchema.parse('VERIFIED')).toBe('VERIFIED')
    expect(releaseStateSchema.parse('BLOCKED')).toBe('BLOCKED')
    expect(() => releaseStateSchema.parse('ACCEPTED')).toThrow()
  })

  it('keeps Package 00C live metadata distinct from local and dev environments', () => {
    expect(packageIdentifierSchema.parse('00C')).toBe('00C')
    expect(() => packageIdentifierSchema.parse('01')).toThrow()
    expect(applicationEnvironmentSchema.parse('live')).toBe('live')
  })
})
