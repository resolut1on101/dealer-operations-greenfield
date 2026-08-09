import { describe, expect, it } from 'vitest'
import { applicationEnvironmentSchema } from '@dealer-operations/contracts'

describe('application environment contract', () => {
  it('accepts only the three defined environments', () => {
    expect(applicationEnvironmentSchema.parse('local')).toBe('local')
    expect(applicationEnvironmentSchema.parse('dev')).toBe('dev')
    expect(applicationEnvironmentSchema.parse('live')).toBe('live')
    expect(() => applicationEnvironmentSchema.parse('staging')).toThrow()
  })
})
