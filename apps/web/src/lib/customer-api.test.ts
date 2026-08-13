import { describe, expect, it } from 'vitest'
import { filterCustomers, getCustomerFilterOptions, getCustomerPaginationItems, getCustomerSortOrders, getPageRange, mapPortfolioMetadata, reconcileCustomerFilters, requireExactCustomerCount, sanitizeCustomerSearchTerm, type CustomerFilters, type CustomerRecord } from './customer-api'

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

  it('exposes representative/chief filters only from the authoritative active hierarchy', () => {
    const options = getCustomerFilterOptions([
      ...resolvedCustomers,
      { ...resolvedCustomers[0], customerId: '004', representative: 'Raw Only Rep', chief: null },
      { ...resolvedCustomers[0], customerId: '005', status: 'PASSIVE', representative: 'Passive Rep', chief: 'Passive Chief' },
    ])

    expect(options.representative).not.toContain('Raw Only Rep')
    expect(options.representative).not.toContain('Passive Rep')
    expect(options.chief).not.toContain('Passive Chief')
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


  it('searches representative and chief names, not just identity fields', () => {
    expect(filterCustomers(resolvedCustomers, { ...empty, search: 'rep b' }).map((row) => row.customerId)).toEqual(['002', '003'])
    expect(filterCustomers(resolvedCustomers, { ...empty, search: 'şef a' }).map((row) => row.customerId)).toEqual(['001'])
  })
})

describe('server-pagination request boundaries', () => {
  it('requests a distinct second page at the exact page-size boundary', () => {
    expect(getPageRange(0, 50)).toEqual({ from: 0, to: 49 })
    expect(getPageRange(1, 50)).toEqual({ from: 50, to: 99 })
  })

  it('covers every row exactly once with deterministic, non-overlapping ranges', () => {
    const ranges = Array.from({ length: Math.ceil(1195 / 50) }, (_, page) => getPageRange(page, 50))
    const positions = ranges.flatMap(({ from, to }) => Array.from({ length: Math.min(to, 1194) - from + 1 }, (_, index) => from + index))
    expect(positions).toHaveLength(1195)
    expect(new Set(positions)).toHaveLength(1195)
    expect(positions[0]).toBe(0)
    expect(positions.at(-1)).toBe(1194)
  })
})


describe('customer pagination metadata', () => {
  it('never silently treats a page-length response as the total when exact count is missing', () => {
    expect(() => requireExactCustomerCount(null)).toThrow('Müşteri toplam kayıt sayısı alınamadı.')
    expect(requireExactCustomerCount(1195)).toBe(1195)
  })

  it('shows compact, directly clickable page numbers across a 24-page portfolio', () => {
    expect(getCustomerPaginationItems(0, 24)).toEqual([0, 1, 'end-ellipsis', 23])
    expect(getCustomerPaginationItems(11, 24)).toEqual([0, 'start-ellipsis', 10, 11, 12, 'end-ellipsis', 23])
    expect(getCustomerPaginationItems(23, 24)).toEqual([0, 'start-ellipsis', 22, 23])
  })
})


describe('portfolio metadata mapping', () => {
  it('maps lightweight server metadata without needing the full customer universe', () => {
    expect(mapPortfolioMetadata({
      total_count: '1195',
      open_count: 700,
      closed_count: '495',
      unclassified_count: 0,
      channels: ['OPEN', 'CLOSED', 'OPEN'],
      segments: ['B', 'A'],
      representatives: ['Rep B', 'Rep A'],
      chiefs: ['Şef B', 'Şef A'],
    })).toEqual({
      totalCount: 1195,
      openCount: 700,
      closedCount: 495,
      unclassifiedCount: 0,
      filterOptions: {
        status: ['ACTIVE'],
        channel: ['CLOSED', 'OPEN'],
        segment: ['A', 'B'],
        representative: ['Rep A', 'Rep B'],
        chief: ['Şef A', 'Şef B'],
      },
    })
  })

  it('sanitizes PostgREST filter grammar and wildcard characters from free-text search', () => {
    expect(sanitizeCustomerSearchTerm('  Rep (A), %_*  ')).toBe('Rep A')
    expect(sanitizeCustomerSearchTerm('A.Ş.')).toBe('A.Ş.')
  })
})


describe('saved customer filter reconciliation', () => {
  it('drops stale hierarchy/filter values while preserving free-text search', () => {
    const filters: CustomerFilters = { search: 'alpha', status: 'PASSIVE', channel: 'OLD', segment: 'A', representative: 'Former Rep', chief: 'Former Chief' }
    expect(reconcileCustomerFilters(filters, {
      status: ['ACTIVE'],
      channel: ['OPEN', 'CLOSED'],
      segment: ['A', 'B'],
      representative: ['Rep A'],
      chief: ['Şef A'],
    })).toEqual({ search: 'alpha', status: '', channel: '', segment: 'A', representative: '', chief: '' })
  })
})
