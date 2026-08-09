import { describe, expect, it } from 'vitest'
import { getVisibleNavGroups } from './navigation'

function itemsFor(role: 'admin' | 'viewer' | null) {
  return getVisibleNavGroups(role).flatMap((group) => group.items)
}

describe('shell navigation visibility', () => {
  it('does not expose mutation surfaces to a viewer or an unauthenticated user', () => {
    expect(itemsFor('viewer')).not.toContain('Veri Yükleme')
    expect(itemsFor('viewer')).not.toContain('Ayarlar')
    expect(itemsFor(null)).not.toContain('Veri Yükleme')
    expect(itemsFor(null)).toContain('Sistem Sağlığı')
  })

  it('keeps management mutation navigation available to an admin', () => {
    expect(itemsFor('admin')).toContain('Veri Yükleme')
    expect(itemsFor('admin')).toContain('Ayarlar')
  })
})
