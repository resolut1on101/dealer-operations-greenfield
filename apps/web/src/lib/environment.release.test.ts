import { describe, expect, it } from 'vitest'
import { applicationEnvironmentSchema, packageIdentifierSchema, releaseStateSchema } from '@dealer-operations/contracts'

describe('Package 01 release metadata contract', () => {
  it('permits only observable release states', () => {
    expect(releaseStateSchema.parse('LIVE_TESTING')).toBe('LIVE_TESTING')
    expect(releaseStateSchema.parse('VERIFIED')).toBe('VERIFIED')
    expect(releaseStateSchema.parse('BLOCKED')).toBe('BLOCKED')
    expect(() => releaseStateSchema.parse('ACCEPTED')).toThrow()
  })

  it('validates Package 01 package identifiers and live environment', () => {
    expect(packageIdentifierSchema.parse('00C')).toBe('00C')
    expect(packageIdentifierSchema.parse('01')).toBe('01')
    expect(() => packageIdentifierSchema.parse('02')).toThrow()
    expect(applicationEnvironmentSchema.parse('live')).toBe('live')
  })
})
