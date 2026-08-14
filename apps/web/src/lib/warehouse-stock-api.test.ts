import { describe, expect, it } from 'vitest'
import { filterWarehouseStockRows, mapWarehouseStockRow, mapWarehouseStockUiSummary, requiresLargeLpuConfirmation, sortWarehouseStockRows } from './warehouse-stock-api'

const sourcePublishedAt = '2026-08-14T11:57:00.000Z'
const rows = [
  mapWarehouseStockRow({ scope_key: '1237', product_code: '150021', product_name: 'EFES PİLSEN', exact_available_quantity: '10.75', lpu: '12', available_litres: '129', litre_resolution_state: 'RESOLVED', source_published_at: sourcePublishedAt }),
  mapWarehouseStockRow({ scope_key: '1237', product_code: '3046', product_name: 'CO2', exact_available_quantity: '5', lpu: null, available_litres: null, litre_resolution_state: 'PARTIAL', source_published_at: sourcePublishedAt }),
  mapWarehouseStockRow({ scope_key: '1237', product_code: '152327', product_name: 'CHIVAS', exact_available_quantity: '197', lpu: '0.7', available_litres: '137.9', litre_resolution_state: 'RESOLVED', source_published_at: sourcePublishedAt }),
]

describe('Package 03AU warehouse stock UI mapping', () => {
  it('maps exact numeric strings and preserves missing LPU as null', () => {
    expect(rows[0].exactAvailableQuantity).toBe(10.75)
    expect(rows[1].lpu).toBeNull()
    expect(rows[1].availableLitres).toBeNull()
  })
  it('keeps the official total null while summary state is partial', () => {
    const summary = mapWarehouseStockUiSummary({ scope_key: '1237', business_row_count: '63', total_available_litres: null, total_litres_state: 'PARTIAL', litre_resolved_count: '58', litre_partial_count: '5', source_published_at: sourcePublishedAt })
    expect(summary.totalAvailableLitres).toBeNull()
  })
  it('normalizes timezone-offset datetime strings into canonical UTC ISO values', () => {
    const row = mapWarehouseStockRow({
      scope_key: '1237',
      product_code: '150021',
      product_name: 'EFES PİLSEN',
      exact_available_quantity: '10',
      lpu: '12',
      available_litres: '120',
      litre_resolution_state: 'RESOLVED',
      source_published_at: '2026-08-14T14:57:00+03:00',
    })
    expect(row.sourcePublishedAt).toBe('2026-08-14T11:57:00.000Z')

    const summary = mapWarehouseStockUiSummary({
      scope_key: '1237',
      business_row_count: '63',
      total_available_litres: '120',
      total_litres_state: 'RESOLVED',
      litre_resolved_count: '63',
      litre_partial_count: '0',
      source_published_at: '2026-08-14T14:57:00+03:00',
    })
    expect(summary.sourcePublishedAt).toBe('2026-08-14T11:57:00.000Z')
  })
  it('rejects invalid publication datetime strings', () => {
    expect(() =>
      mapWarehouseStockRow({
        scope_key: '1237',
        product_code: '150021',
        product_name: 'EFES PİLSEN',
        exact_available_quantity: '10',
        lpu: '12',
        available_litres: '120',
        litre_resolution_state: 'RESOLVED',
        source_published_at: 'not-a-date',
      })
    ).toThrow('Yayın zamanı geçersiz.')
  })
})

describe('Package 03AU warehouse stock list behavior', () => {
  it('searches product code and product name with one search box', () => {
    expect(filterWarehouseStockRows(rows, '150021', 'all')).toHaveLength(1)
    expect(filterWarehouseStockRows(rows, 'chivas', 'all')[0].productCode).toBe('152327')
  })
  it('filters only the explicit litre state', () => {
    expect(filterWarehouseStockRows(rows, '', 'partial').map((row) => row.productCode)).toEqual(['3046'])
  })
  it('sorts by product name and keeps missing total litres at the bottom', () => {
    expect(sortWarehouseStockRows(rows, { key: 'productName', ascending: true }).map((row) => row.productName)).toEqual(['CHIVAS', 'CO2', 'EFES PİLSEN'])
    expect(sortWarehouseStockRows(rows, { key: 'totalLitres', ascending: false }).map((row) => row.productCode)).toEqual(['152327', '150021', '3046'])
  })
  it('flags a 25 percent-or-larger LPU change for confirmation', () => {
    expect(requiresLargeLpuConfirmation(12, 15)).toBe(true)
    expect(requiresLargeLpuConfirmation(12, 14.99)).toBe(false)
    expect(requiresLargeLpuConfirmation(null, 12)).toBe(false)
  })
})
