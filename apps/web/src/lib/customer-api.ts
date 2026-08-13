import { supabase } from './supabase'

export type CustomerRecord = {
  customerId: string
  customerName: string | null
  tradeName: string | null
  status: string
  channel: string
  segment: string | null
  representative: string | null
  chief: string | null
}

export type CustomerFilters = { search: string; status: string; channel: string; segment: string; representative: string; chief: string }
export type CustomerPage = { rows: CustomerRecord[]; count: number }
export type CustomerSortKey = 'customerName' | 'customerId' | 'tradeName' | 'status' | 'channel' | 'segment' | 'representative' | 'chief'
export type CustomerSort = { key: CustomerSortKey; ascending: boolean }
export type CustomerFilterOptions = { status: string[]; channel: string[]; segment: string[]; representative: string[]; chief: string[] }
export type CustomerProvenance = { snapshotId: string; batchId: string; contract: string; publication: string; status: string; matched: boolean }
export type CustomerPortfolioMetadata = {
  totalCount: number
  openCount: number
  closedCount: number
  unclassifiedCount: number
  filterOptions: CustomerFilterOptions
}
export type CustomerOrganizationAggregate = {
  chief: string
  representative: string
  channel: string
  segment: string | null
  customerCount: number
}

type SafeCustomerRow = {
  customer_id: string; customer_name: string | null; trade_name: string | null; status: string; channel: string; segment: string | null; representative: string | null; chief: string | null
}
type PortfolioMetadataRow = {
  total_count: number | string
  open_count: number | string
  closed_count: number | string
  unclassified_count: number | string
  channels: string[] | null
  segments: string[] | null
  representatives: string[] | null
  chiefs: string[] | null
}
type OrganizationAggregateRow = {
  chief: string
  representative: string
  channel: string
  segment: string | null
  customer_count: number | string
}

function api() { if (!supabase) throw new Error('Supabase bağlantısı yapılandırılmamış.'); return supabase }
function mapRow(row: SafeCustomerRow): CustomerRecord { return { customerId: row.customer_id, customerName: row.customer_name, tradeName: row.trade_name, status: row.status, channel: row.channel, segment: row.segment, representative: row.representative, chief: row.chief } }
const sortFields: Record<CustomerSortKey, string> = { customerName: 'customer_name', customerId: 'customer_id', tradeName: 'trade_name', status: 'status', channel: 'channel', segment: 'segment', representative: 'representative', chief: 'chief' }
export type CustomerSortOrder = { field: string; ascending: boolean }
export function getCustomerSortOrders(sort: CustomerSort): CustomerSortOrder[] { const primary = { field: sortFields[sort.key], ascending: sort.ascending }; return sort.key === 'customerId' ? [primary] : [primary, { field: 'customer_id', ascending: true }] }

export function getPageRange(page: number, pageSize: number) { return { from: page * pageSize, to: page * pageSize + pageSize - 1 } }

export function requireExactCustomerCount(count: number | null): number {
  if (typeof count !== 'number') throw new Error('Müşteri toplam kayıt sayısı alınamadı.')
  return count
}

export type CustomerPaginationItem = number | 'start-ellipsis' | 'end-ellipsis'
export function getCustomerPaginationItems(currentPage: number, pageCount: number): CustomerPaginationItem[] {
  if (pageCount <= 0) return []
  if (pageCount <= 7) return Array.from({ length: pageCount }, (_, index) => index)
  const wanted = [...new Set([0, pageCount - 1, currentPage - 1, currentPage, currentPage + 1].filter((index) => index >= 0 && index < pageCount))].sort((a, b) => a - b)
  const result: CustomerPaginationItem[] = []
  wanted.forEach((value, index) => {
    const previous = wanted[index - 1]
    if (index > 0 && value - previous === 2) result.push(previous + 1)
    else if (index > 0 && value - previous > 2) result.push(value < currentPage ? 'start-ellipsis' : 'end-ellipsis')
    result.push(value)
  })
  return result
}

export function sanitizeCustomerSearchTerm(value: string): string {
  return value.trim().replace(/[,()%*_"]/g, ' ').replace(/\s+/g, ' ').trim()
}

export async function listCustomers(filters: CustomerFilters, page: number, pageSize: number, sort: CustomerSort = { key: 'customerId', ascending: true }): Promise<CustomerPage> {
  const { from, to } = getPageRange(page, pageSize)
  // Exact count belongs on rpc() options. Passing it to the post-RPC select() modifier
  // does not request a Content-Range count and makes the UI incorrectly treat a 50-row
  // page as the entire result set.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let query = api().rpc('read_current_customer_business_surface', {}, { count: 'exact' }) as any
  for (const order of getCustomerSortOrders(sort)) query = query.order(order.field, { ascending: order.ascending })
  const search = sanitizeCustomerSearchTerm(filters.search)
  if (search) {
    const pattern = `%${search}%`
    query = query.or(`customer_id.ilike.${pattern},customer_name.ilike.${pattern},trade_name.ilike.${pattern},representative.ilike.${pattern},chief.ilike.${pattern}`)
  }
  // Status is a database-enforced invariant of this surface; a stale saved UI
  // preference must not turn the active portfolio into a client-side scope.
  if (filters.channel) query = query.eq('channel', filters.channel)
  if (filters.segment) query = query.eq('segment', filters.segment)
  if (filters.representative) query = query.eq('representative', filters.representative)
  if (filters.chief) query = query.eq('chief', filters.chief)
  const { data, error, count } = await query.range(from, to)
  if (error) throw error
  const rows = ((data ?? []) as unknown as SafeCustomerRow[]).map(mapRow)
  return { rows, count: requireExactCustomerCount(count) }
}

export function filterCustomers(rows: CustomerRecord[], filters: CustomerFilters): CustomerRecord[] {
  const search = filters.search.trim().toLocaleLowerCase('tr')
  return rows.filter((row) => (!search || [row.customerId, row.customerName, row.tradeName, row.representative, row.chief].some((value) => value?.toLocaleLowerCase('tr').includes(search))) && (!filters.status || row.status === filters.status) && (!filters.channel || row.channel === filters.channel) && (!filters.segment || row.segment === filters.segment) && (!filters.representative || row.representative === filters.representative) && (!filters.chief || row.chief === filters.chief))
}

export function reconcileCustomerFilters(filters: CustomerFilters, options: CustomerFilterOptions): CustomerFilters {
  return {
    search: filters.search,
    status: '',
    channel: filters.channel && options.channel.includes(filters.channel) ? filters.channel : '',
    segment: filters.segment && options.segment.includes(filters.segment) ? filters.segment : '',
    representative: filters.representative && options.representative.includes(filters.representative) ? filters.representative : '',
    chief: filters.chief && options.chief.includes(filters.chief) ? filters.chief : '',
  }
}

export function getCustomerFilterOptions(rows: CustomerRecord[]): CustomerFilterOptions {
  const optionValues = (field: 'status' | 'channel' | 'segment') => [...new Set(rows.map((row) => row[field]).filter((value): value is string => Boolean(value)))].sort((a, b) => a.localeCompare(b, 'tr'))
  const authoritativeOrganizationRows = rows.filter((row) => row.status === 'ACTIVE' && row.representative && row.chief)
  const representatives = [...new Set(authoritativeOrganizationRows.map((row) => row.representative).filter((value): value is string => Boolean(value)))].sort((a, b) => a.localeCompare(b, 'tr'))
  const chiefs = [...new Set(authoritativeOrganizationRows.map((row) => row.chief).filter((value): value is string => Boolean(value)))].sort((a, b) => a.localeCompare(b, 'tr'))
  return { status: optionValues('status'), channel: optionValues('channel'), segment: optionValues('segment'), representative: representatives, chief: chiefs }
}

function asNumber(value: number | string): number {
  const number = typeof value === 'number' ? value : Number(value)
  if (!Number.isFinite(number)) throw new Error('Müşteri portföy metriği geçersiz.')
  return number
}

function sorted(values: string[] | null): string[] {
  return [...new Set(values ?? [])].filter(Boolean).sort((a, b) => a.localeCompare(b, 'tr'))
}

export function mapPortfolioMetadata(row: PortfolioMetadataRow): CustomerPortfolioMetadata {
  return {
    totalCount: asNumber(row.total_count),
    openCount: asNumber(row.open_count),
    closedCount: asNumber(row.closed_count),
    unclassifiedCount: asNumber(row.unclassified_count),
    filterOptions: {
      status: ['ACTIVE'],
      channel: sorted(row.channels),
      segment: sorted(row.segments),
      representative: sorted(row.representatives),
      chief: sorted(row.chiefs),
    },
  }
}

export async function getCustomerPortfolioMetadata(): Promise<CustomerPortfolioMetadata> {
  const { data, error } = await api().rpc('read_current_customer_portfolio_metadata')
  if (error) throw error
  const row = (data as unknown as PortfolioMetadataRow[] | null)?.[0]
  if (!row) throw new Error('Müşteri portföy özeti alınamadı.')
  return mapPortfolioMetadata(row)
}

export async function listCustomerOrganizationAggregates(): Promise<CustomerOrganizationAggregate[]> {
  const { data, error } = await api().rpc('read_current_customer_organization_aggregates')
  if (error) throw error
  return ((data ?? []) as unknown as OrganizationAggregateRow[]).map((row) => ({
    chief: row.chief,
    representative: row.representative,
    channel: row.channel,
    segment: row.segment,
    customerCount: asNumber(row.customer_count),
  }))
}

export async function getCustomerProvenance(customer: CustomerRecord): Promise<CustomerProvenance | null> {
  const client = api()
  const { data: resolution, error: resolutionError } = await client.from('customer_resolutions').select('snapshot_id').eq('customer_id', customer.customerId).eq('current_snapshot_state', 'PRESENT_IN_CURRENT_MASTER').maybeSingle()
  if (resolutionError) throw resolutionError
  if (!resolution) return null
  const { data: snapshot, error: snapshotError } = await client.from('customer_master_snapshots').select('id,batch_id,publication_id').eq('id', resolution.snapshot_id).single(); if (snapshotError) throw snapshotError
  const { data: batch, error: batchError } = await client.from('import_batches').select('id,status,source_contract_version_id,published_publication_id').eq('id', snapshot.batch_id).single(); if (batchError) throw batchError
  const { data: contract, error: contractError } = await client.from('source_contract_versions').select('source_kind,version').eq('id', batch.source_contract_version_id).single(); if (contractError) throw contractError
  return { snapshotId: snapshot.id, batchId: batch.id, contract: `${contract.source_kind} v${contract.version}`, publication: snapshot.publication_id ?? batch.published_publication_id ?? '—', status: batch.status, matched: batch.status === 'PUBLISHED' }
}
