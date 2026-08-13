import { describe, expect, it } from 'vitest'
import { filterCustomers, getCustomerFilterOptions, getCustomerSortOrders, type CustomerFilters, type CustomerRecord } from './customer-api'

const resolvedCustomers: CustomerRecord[] = [
  { customerId: '001', customerName: 'Bir', tradeName: null, status: 'ACTIVE', channel: 'DIRECT', segment: 'A', representative: 'Rep A', chief: 'Şef A' },
  { customerId: '002', customerName: 'İki', tradeName: null, status: 'PASSIVE', channel: 'DEALER', segment: 'B', representative: 'Rep B', chief: 'Şef B' },
  { customerId: '003', customerName: 'Üç', tradeName: null, status: 'ACTIVE', channel: 'DIRECT', segment: 'A', representative: 'Rep B', chief: 'Şef B' },
]

describe('customer sort order plan', () => {
  it('uses only requested customer id order for customer id sorting', () => {
    expect(getCustomerSortOrders({ key: 'customerId', ascending: false })).toEqual([{ field: 'customer_id', ascending: false }])
  })

  it('adds an ascending customer id tiebreaker for non-unique sorts', () => {
    expect(getCustomerSortOrders({ key: 'status', ascending: false })).toEqual([{ field: 'status', ascending: false }, { field: 'customer_id', ascending: true }])
    expect(getCustomerSortOrders({ key: 'representative', ascending: true })).toEqual([{ field: 'representative', ascending: true }, { field: 'customer_id', ascending: true }])
  })
})

describe('customer filter option universe', () => {
  it('derives all five dimensions from the full resolved population', () => {
    expect(getCustomerFilterOptions(resolvedCustomers)).toEqual({
      status: ['ACTIVE', 'PASSIVE'],
      channel: ['DEALER', 'DIRECT'],
      segment: ['A', 'B'],
      representative: ['Rep A', 'Rep B'],
      chief: ['Şef A', 'Şef B'],
    })
  })

  it('keeps off-page values available when the visible page changes', () => {
    const pageOne = resolvedCustomers.slice(0, 1)
    const pageTwo = resolvedCustomers.slice(1)
    const options = getCustomerFilterOptions(resolvedCustomers)

    expect(pageOne.some((row) => row.representative === 'Rep B')).toBe(false)
    expect(pageTwo.some((row) => row.representative === 'Rep B')).toBe(true)
    expect(options.representative).toContain('Rep B')
    expect(getCustomerFilterOptions(resolvedCustomers)).toEqual(options)
  })

  it('is distinct, Turkish-sorted, and excludes values absent from resolved records', () => {
    const options = getCustomerFilterOptions([
      ...resolvedCustomers,
      { ...resolvedCustomers[0], customerId: '004', representative: 'Çalışan', chief: 'Şef Ç' },
      { ...resolvedCustomers[0], customerId: '005', representative: 'Çalışan', chief: 'Şef Ç' },
    ])

    expect(options.representative).toEqual(['Çalışan', 'Rep A', 'Rep B'])
    expect(options.chief).toEqual(['Şef A', 'Şef B', 'Şef Ç'])
    expect(options.representative).not.toContain('Source Observation Only')
  })
})

describe('viewer-safe customer filtering', () => {
  const empty: CustomerFilters = { search: '', status: '', channel: '', segment: '', representative: '', chief: '' }

  it('composes every active dimension conjunctively and preserves null organization values', () => {
    expect(filterCustomers([
      ...resolvedCustomers,
      { ...resolvedCustomers[0], customerId: '004', customerName: 'Null org', representative: null, chief: null },
    ], { ...empty, status: 'ACTIVE', representative: 'Rep B' }).map((row) => row.customerId)).toEqual(['003'])
    expect(filterCustomers(resolvedCustomers, { ...empty, channel: 'DIRECT', representative: 'Rep B' }).map((row) => row.customerId)).toEqual(['003'])
    expect(filterCustomers(resolvedCustomers, { ...empty, segment: 'B', chief: 'Şef B' }).map((row) => row.customerId)).toEqual(['002'])
    expect(filterCustomers(resolvedCustomers, { ...empty, search: 'İKİ', chief: 'Şef B' }).map((row) => row.customerId)).toEqual(['002'])
    expect(filterCustomers(resolvedCustomers, { ...empty, representative: 'Rep B', chief: 'Şef B', status: 'ACTIVE', channel: 'DIRECT', segment: 'A', search: 'Üç' }).map((row) => row.customerId)).toEqual(['003'])
    expect(filterCustomers([{ ...resolvedCustomers[0], representative: null, chief: null }], { ...empty, representative: '' })[0].representative).toBeNull()
  })
})
