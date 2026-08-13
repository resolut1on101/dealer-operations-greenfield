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

type SafeCustomerRow = {
  customer_id: string; customer_name: string | null; trade_name: string | null; status: string; channel: string; segment: string | null; representative: string | null; chief: string | null
}

function api() { if (!supabase) throw new Error('Supabase bağlantısı yapılandırılmamış.'); return supabase }
function mapRow(row: SafeCustomerRow): CustomerRecord { return { customerId: row.customer_id, customerName: row.customer_name, tradeName: row.trade_name, status: row.status, channel: row.channel, segment: row.segment, representative: row.representative, chief: row.chief } }
const sortFields: Record<CustomerSortKey, string> = { customerName: 'customer_name', customerId: 'customer_id', tradeName: 'trade_name', status: 'status', channel: 'channel', segment: 'segment', representative: 'representative', chief: 'chief' }
export type CustomerSortOrder = { field: string; ascending: boolean }
export function getCustomerSortOrders(sort: CustomerSort): CustomerSortOrder[] { const primary = { field: sortFields[sort.key], ascending: sort.ascending }; return sort.key === 'customerId' ? [primary] : [primary, { field: 'customer_id', ascending: true }] }

export async function listCustomers(filters: CustomerFilters, page: number, pageSize: number, sort: CustomerSort = { key: 'customerId', ascending: true }): Promise<CustomerPage> {
  const from = page * pageSize
  const to = from + pageSize - 1
  // Supabase's generated RPC builder types omit the count overload even though the runtime supports it.
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  let query = (api().rpc('read_current_customer_business_surface') as any).select('*', { count: 'exact' })
  for (const order of getCustomerSortOrders(sort)) query = query.order(order.field, { ascending: order.ascending })
  const search = filters.search.trim().replace(/[,()]/g, ' ')
  if (search) query = query.or(`customer_id.ilike.%${search}%,customer_name.ilike.%${search}%,trade_name.ilike.%${search}%`)
  if (filters.status) query = query.eq('status', filters.status)
  if (filters.channel) query = query.eq('channel', filters.channel)
  if (filters.segment) query = query.eq('segment', filters.segment)
  if (filters.representative) query = query.eq('representative', filters.representative)
  if (filters.chief) query = query.eq('chief', filters.chief)
  const { data, error, count } = await query.range(from, to)
  if (error) throw error
  const rows = ((data ?? []) as unknown as SafeCustomerRow[]).map(mapRow)
  return { rows, count: count ?? rows.length }
}

export async function listAllCustomers(): Promise<CustomerRecord[]> {
  const rows: CustomerRecord[] = []; const pageSize = 1000; let page = 0
  while (true) { const result = await listCustomers({ search: '', status: '', channel: '', segment: '', representative: '', chief: '' }, page, pageSize); rows.push(...result.rows); if (result.rows.length < pageSize) return rows; page += 1 }
}

export function filterCustomers(rows: CustomerRecord[], filters: CustomerFilters): CustomerRecord[] {
  const search = filters.search.trim().toLocaleLowerCase('tr')
  return rows.filter((row) => (!search || [row.customerId, row.customerName, row.tradeName].some((value) => value?.toLocaleLowerCase('tr').includes(search))) && (!filters.status || row.status === filters.status) && (!filters.channel || row.channel === filters.channel) && (!filters.segment || row.segment === filters.segment) && (!filters.representative || row.representative === filters.representative) && (!filters.chief || row.chief === filters.chief))
}

export function getCustomerFilterOptions(rows: CustomerRecord[]): CustomerFilterOptions {
  const optionValues = (field: 'status' | 'channel' | 'segment') => [...new Set(rows.map((row) => row[field]).filter((value): value is string => Boolean(value)))].sort((a, b) => a.localeCompare(b, 'tr'))
  // Representative/chief options must come only from the authoritative ACTIVE hierarchy.
  // A raw or resolved representative without a materialized canonical chief is not a valid
  // organization/filter choice for P02U.
  const authoritativeOrganizationRows = rows.filter((row) => row.status === 'ACTIVE' && row.representative && row.chief)
  const representatives = [...new Set(authoritativeOrganizationRows.map((row) => row.representative).filter((value): value is string => Boolean(value)))].sort((a, b) => a.localeCompare(b, 'tr'))
  const chiefs = [...new Set(authoritativeOrganizationRows.map((row) => row.chief).filter((value): value is string => Boolean(value)))].sort((a, b) => a.localeCompare(b, 'tr'))
  return { status: optionValues('status'), channel: optionValues('channel'), segment: optionValues('segment'), representative: representatives, chief: chiefs }
}
export async function listCustomerFilterOptions(): Promise<CustomerFilterOptions> { return getCustomerFilterOptions(await listAllCustomers()) }
export async function listCustomerFilterValues(field: keyof CustomerFilterOptions) { return (await listCustomerFilterOptions())[field] }

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
