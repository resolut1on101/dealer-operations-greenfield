import {
  warehouseStockBusinessRowSchema,
  warehouseStockUiSummarySchema,
  type WarehouseStockBusinessRow,
  type WarehouseStockUiSummary,
} from '@dealer-operations/contracts'
import { supabase } from './supabase'

type Numeric = number | string

type WarehouseStockDbRow = {
  scope_key: string
  product_code: string
  product_name: string | null
  exact_available_quantity: Numeric
  lpu: Numeric | null
  available_litres: Numeric | null
  litre_resolution_state: 'RESOLVED' | 'PARTIAL'
  source_published_at: string
}

type WarehouseStockUiSummaryDbRow = {
  scope_key: string
  business_row_count: Numeric
  total_available_litres: Numeric | null
  total_litres_state: 'RESOLVED' | 'PARTIAL'
  litre_resolved_count: Numeric
  litre_partial_count: Numeric
  source_published_at: string
}

type LpuMutationDbRow = { updated_count: Numeric; remaining_missing_count: Numeric }

export type WarehouseStockLpuUpdate = { productCode: string; lpu: number }
export type WarehouseStockLpuMutationResult = { updatedCount: number; remainingMissingCount: number }
export type WarehouseStockSortKey = 'productName' | 'stock' | 'totalLitres'
export type WarehouseStockSort = { key: WarehouseStockSortKey; ascending: boolean }
export type WarehouseStockLitreFilter = 'all' | 'resolved' | 'partial'

function api() {
  if (!supabase) throw new Error('Supabase bağlantısı yapılandırılmamış.')
  return supabase
}

function asNumber(value: Numeric, label: string): number {
  const parsed = typeof value === 'number' ? value : Number(value)
  if (!Number.isFinite(parsed)) throw new Error(`${label} geçersiz.`)
  return parsed
}

function asNullableNumber(value: Numeric | null, label: string): number | null {
  return value === null ? null : asNumber(value, label)
}

export function mapWarehouseStockRow(row: WarehouseStockDbRow): WarehouseStockBusinessRow {
  return warehouseStockBusinessRowSchema.parse({
    scopeKey: row.scope_key,
    productCode: row.product_code,
    productName: row.product_name,
    exactAvailableQuantity: asNumber(row.exact_available_quantity, 'Stok miktarı'),
    lpu: asNullableNumber(row.lpu, 'Litre / Birim'),
    availableLitres: asNullableNumber(row.available_litres, 'Toplam litre'),
    litreResolutionState: row.litre_resolution_state,
    sourcePublishedAt: row.source_published_at,
  })
}

export function mapWarehouseStockUiSummary(row: WarehouseStockUiSummaryDbRow): WarehouseStockUiSummary {
  return warehouseStockUiSummarySchema.parse({
    scopeKey: row.scope_key,
    businessRowCount: asNumber(row.business_row_count, 'Toplam ürün'),
    totalAvailableLitres: asNullableNumber(row.total_available_litres, 'Toplam litre'),
    totalLitresState: row.total_litres_state,
    litreResolvedCount: asNumber(row.litre_resolved_count, 'Hesaplanan litre sayısı'),
    litrePartialCount: asNumber(row.litre_partial_count, 'Eksik litre sayısı'),
    sourcePublishedAt: row.source_published_at,
  })
}

export async function getWarehouseStockUiSummary(): Promise<WarehouseStockUiSummary> {
  const { data, error } = await api().rpc('read_current_warehouse_stock_ui_summary')
  if (error) throw error
  const rows = (data ?? []) as unknown as WarehouseStockUiSummaryDbRow[]
  if (rows.length === 0) throw new Error('Aktif depo stoku yayını bulunamadı.')
  if (rows.length !== 1) throw new Error('Birden fazla aktif depo stoku kapsamı bulundu. Bu yüzey tek aktif bayi kapsamı bekliyor.')
  return mapWarehouseStockUiSummary(rows[0])
}

export async function listWarehouseStockRows(scopeKey: string): Promise<WarehouseStockBusinessRow[]> {
  const { data, error } = await api().rpc('read_current_warehouse_stock_ui').eq('scope_key', scopeKey)
  if (error) throw error
  return ((data ?? []) as unknown as WarehouseStockDbRow[]).map(mapWarehouseStockRow)
}

export async function loadWarehouseStockWorkspace(): Promise<{ summary: WarehouseStockUiSummary; rows: WarehouseStockBusinessRow[] }> {
  const summary = await getWarehouseStockUiSummary()
  const rows = await listWarehouseStockRows(summary.scopeKey)
  return { summary, rows }
}

function normalizeSearchText(value: string | null | undefined): string {
  return (value ?? '')
    .trim()
    .toLocaleLowerCase('tr-TR')
    .replaceAll('ı', 'i')
}

export function filterWarehouseStockRows(rows: WarehouseStockBusinessRow[], search: string, litreFilter: WarehouseStockLitreFilter) {
  const term = normalizeSearchText(search)
  return rows.filter((row) => {
    const searchMatches = !term || normalizeSearchText(row.productCode).includes(term) || normalizeSearchText(row.productName).includes(term)
    const stateMatches = litreFilter === 'all' || (litreFilter === 'resolved' ? row.litreResolutionState === 'RESOLVED' : row.litreResolutionState === 'PARTIAL')
    return searchMatches && stateMatches
  })
}

export function sortWarehouseStockRows(rows: WarehouseStockBusinessRow[], sort: WarehouseStockSort) {
  const copy = [...rows]
  const sign = sort.ascending ? 1 : -1
  return copy.sort((left, right) => {
    if (sort.key === 'productName') {
      const primary = (left.productName ?? '').localeCompare(right.productName ?? '', 'tr-TR', { sensitivity: 'base' })
      return primary !== 0 ? primary * sign : left.productCode.localeCompare(right.productCode, 'tr-TR')
    }
    const leftValue = sort.key === 'stock' ? left.exactAvailableQuantity : left.availableLitres
    const rightValue = sort.key === 'stock' ? right.exactAvailableQuantity : right.availableLitres
    if (leftValue === null && rightValue === null) return left.productCode.localeCompare(right.productCode, 'tr-TR')
    if (leftValue === null) return 1
    if (rightValue === null) return -1
    if (leftValue === rightValue) return left.productCode.localeCompare(right.productCode, 'tr-TR')
    return (leftValue - rightValue) * sign
  })
}

export function requiresLargeLpuConfirmation(current: number | null, next: number): boolean {
  if (current === null || current <= 0 || next <= 0) return false
  return Math.abs(next - current) / current >= 0.25
}

export async function saveWarehouseStockLpuUpdates(scopeKey: string, updates: WarehouseStockLpuUpdate[], confirmLargeChange = false): Promise<WarehouseStockLpuMutationResult> {
  if (!updates.length) return { updatedCount: 0, remainingMissingCount: 0 }
  const { data, error } = await api().rpc('set_warehouse_stock_lpu_overrides', {
    p_scope_key: scopeKey,
    p_updates: updates.map((update) => ({ product_code: update.productCode, lpu: update.lpu })),
    p_confirm_large_change: confirmLargeChange,
  })
  if (error) throw error
  const row = ((data ?? []) as unknown as LpuMutationDbRow[])[0]
  if (!row) throw new Error('Litre / Birim güncelleme sonucu alınamadı.')
  return { updatedCount: asNumber(row.updated_count, 'Güncellenen ürün sayısı'), remainingMissingCount: asNumber(row.remaining_missing_count, 'Eksik ürün sayısı') }
}
