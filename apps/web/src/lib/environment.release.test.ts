import { describe, expect, it } from 'vitest'
import { applicationEnvironmentSchema, packageIdentifierSchema, releaseStateSchema } from '@dealer-operations/contracts'

describe('Package release metadata contract', () => {
  it('permits only observable release states', () => {
    expect(releaseStateSchema.parse('LIVE_TESTING')).toBe('LIVE_TESTING')
    expect(releaseStateSchema.parse('VERIFIED')).toBe('VERIFIED')
    expect(releaseStateSchema.parse('BLOCKED')).toBe('BLOCKED')
    expect(() => releaseStateSchema.parse('ACCEPTED')).toThrow()
  })

  it('validates current package identifiers and live environment', () => {
    expect(packageIdentifierSchema.parse('00C')).toBe('00C')
    expect(packageIdentifierSchema.parse('01')).toBe('01')
    expect(packageIdentifierSchema.parse('02')).toBe('02')
    expect(packageIdentifierSchema.parse('02U')).toBe('02U')
    expect(packageIdentifierSchema.parse('03')).toBe('03')
    expect(packageIdentifierSchema.parse('03A')).toBe('03A')
    expect(packageIdentifierSchema.parse('03AU')).toBe('03AU')
    expect(applicationEnvironmentSchema.parse('live')).toBe('live')
  })
})
