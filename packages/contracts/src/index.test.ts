import { describe, expect, it } from 'vitest'
import { applicationRoleSchema } from './index'

describe('application role contract', () => {
  it('permits only admin and viewer', () => {
    expect(applicationRoleSchema.parse('admin')).toBe('admin')
    expect(applicationRoleSchema.parse('viewer')).toBe('viewer')
    expect(() => applicationRoleSchema.parse('editor')).toThrow()
  })
})
