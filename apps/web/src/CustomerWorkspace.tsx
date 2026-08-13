import { useCallback, useEffect, useMemo, useRef, useState, type CSSProperties, type KeyboardEvent, type ReactNode } from 'react'
import type { ApplicationRole } from '@dealer-operations/contracts'
import { releasePackage } from './lib/environment'
import {
  type CustomerFilters,
  type CustomerFilterOptions,
  type CustomerProvenance,
  type CustomerRecord,
  type CustomerSort,
  type CustomerSortKey,
  getCustomerFilterOptions,
  getCustomerProvenance,
  listAllCustomers,
  listCustomers,
} from './lib/customer-api'

const PAGE_SIZE = 50
const emptyFilters: CustomerFilters = { search: '', status: '', channel: '', segment: '', representative: '', chief: '' }
type View = 'customers' | 'organization'

type OrgSelection = { chief: string | null; representative: string | null }

function display(value: string | null | undefined) { return value?.trim() || '—' }
function initials(value: string | null | undefined) { return display(value).split(/\s+/).filter(Boolean).slice(0, 2).map((part) => part[0]).join('').toLocaleUpperCase('tr-TR') }
function personName(value: string | null | undefined) {
  const normalized = value?.trim().replace(/\s+/g, ' ')
  if (!normalized) return '—'
  return normalized
    .toLocaleLowerCase('tr-TR')
    .split(' ')
    .map((word) => word ? `${word.slice(0, 1).toLocaleUpperCase('tr-TR')}${word.slice(1)}` : word)
    .join(' ')
}
function channelLabel(value: string) {
  if (value === 'OPEN') return 'Açık Kanal'
  if (value === 'CLOSED') return 'Kapalı Kanal'
  if (value === 'UNCLASSIFIED') return 'Sınıflandırılmamış'
  return value
}
function statusLabel(value: string) {
  if (value === 'ACTIVE') return 'Aktif'
  if (value === 'PASSIVE') return 'Pasif'
  if (value === 'CANCELLED') return 'İptal'
  if (value === 'UNKNOWN') return 'Bilinmiyor'
  return value
}
function statusClass(value: string) {
  if (value === 'ACTIVE') return 'active'
  if (value === 'PASSIVE') return 'passive'
  if (value === 'CANCELLED') return 'cancelled'
  return 'unknown'
}
function channelClass(value: string) { return value === 'OPEN' ? 'open' : value === 'CLOSED' ? 'closed' : 'unclassified' }
function copyValue(value: string, onCopied: () => void) {
  void (navigator.clipboard ? navigator.clipboard.writeText(value) : Promise.reject(new Error('Clipboard unavailable')))
    .then(onCopied)
    .catch(() => undefined)
}
function counts(values: string[]) {
  const result = new Map<string, number>()
  values.forEach((value) => result.set(value, (result.get(value) ?? 0) + 1))
  return [...result.entries()].sort((a, b) => b[1] - a[1] || a[0].localeCompare(b[0], 'tr'))
}
function loadPreference<T>(key: string, fallback: T): T {
  try { const stored = localStorage.getItem(key); return stored ? JSON.parse(stored) as T : fallback } catch { return fallback }
}
function savePreference<T>(key: string, value: T) {
  try { localStorage.setItem(key, JSON.stringify(value)) } catch { /* optional preference */ }
}

export function CustomerWorkspace({ role }: { role: ApplicationRole }) {
  const admin = role === 'admin'
  const [view, setView] = useState<View>('customers')
  const [filters, setFilters] = useState(() => loadPreference('p02u-v7-filters', emptyFilters))
  const [page, setPage] = useState(0)
  const [sort, setSort] = useState<CustomerSort>({ key: 'customerId', ascending: true })
  const [customerPage, setCustomerPage] = useState({ rows: [] as CustomerRecord[], count: 0 })
  const [allCustomers, setAllCustomers] = useState<CustomerRecord[]>([])
  const [filterOptions, setFilterOptions] = useState<CustomerFilterOptions | null>(null)
  const [filterOptionsError, setFilterOptionsError] = useState('')
  const [loading, setLoading] = useState(true)
  const [allLoading, setAllLoading] = useState(true)
  const [customerError, setCustomerError] = useState('')
  const [organizationError, setOrganizationError] = useState('')
  const [drawerCustomer, setDrawerCustomer] = useState<CustomerRecord | null>(null)
  const [provenance, setProvenance] = useState<CustomerProvenance | null>(null)
  const [provenanceLoading, setProvenanceLoading] = useState(false)
  const [provenanceError, setProvenanceError] = useState('')
  const [toast, setToast] = useState('')
  const [mobileFiltersOpen, setMobileFiltersOpen] = useState(false)
  const [orgSelection, setOrgSelection] = useState<OrgSelection>({ chief: null, representative: null })
  const listRequestId = useRef(0)
  const provenanceRequestId = useRef(0)
  const triggerRef = useRef<HTMLElement | null>(null)

  const applyCustomerUniverse = useCallback((rows: CustomerRecord[]) => {
    setAllCustomers(rows)
    setFilterOptions(getCustomerFilterOptions(rows))
    setFilterOptionsError('')
    setAllLoading(false)
  }, [])

  const refresh = useCallback(async () => {
    const requestId = ++listRequestId.current
    setLoading(true)
    setCustomerError('')
    try {
      const result = await listCustomers(filters, page, PAGE_SIZE, sort)
      if (requestId !== listRequestId.current) return
      setCustomerPage(result)
    } catch (cause) {
      if (requestId === listRequestId.current) setCustomerError(cause instanceof Error ? cause.message : 'Müşteri verisi okunamadı.')
    } finally {
      if (requestId === listRequestId.current) setLoading(false)
    }
  }, [filters, page, sort])

  useEffect(() => { void refresh() }, [refresh])
  useEffect(() => {
    setAllLoading(true)
    void listAllCustomers()
      .then(applyCustomerUniverse)
      .catch((cause) => {
        setFilterOptionsError(cause instanceof Error ? cause.message : 'Filtre seçenekleri okunamadı.')
        setOrganizationError(cause instanceof Error ? cause.message : 'Organizasyon verisi okunamadı.')
        setAllLoading(false)
      })
  }, [applyCustomerUniverse])
  useEffect(() => { savePreference('p02u-v7-filters', filters) }, [filters])

  const organizationCustomers = useMemo(
    () => allCustomers.filter((customer) => customer.status === 'ACTIVE' && customer.representative && customer.chief),
    [allCustomers],
  )
  const chiefs = useMemo(
    () => [...new Set(organizationCustomers.map((customer) => customer.chief).filter((value): value is string => Boolean(value)))].sort((a, b) => personName(a).localeCompare(personName(b), 'tr')),
    [organizationCustomers],
  )

  useEffect(() => {
    if (view !== 'organization' || !chiefs.length) return
    setOrgSelection((current) => {
      if (current.chief && chiefs.includes(current.chief)) return current
      return { chief: chiefs[0], representative: null }
    })
  }, [chiefs, view])

  function updateFilter(key: keyof CustomerFilters, value: string) {
    setPage(0)
    setFilters((current) => ({ ...current, [key]: value }))
  }
  function clearFilters() { setPage(0); setFilters(emptyFilters) }
  function notify(message: string) { setToast(message); window.setTimeout(() => setToast(''), 1800) }
  function copyCustomerId(id: string) { copyValue(id, () => notify('Müşteri no kopyalandı.')) }
  function openDrawer(customer: CustomerRecord, trigger?: HTMLElement | null) {
    const requestId = ++provenanceRequestId.current
    triggerRef.current = trigger ?? document.activeElement as HTMLElement
    setDrawerCustomer(customer)
    setProvenance(null)
    setProvenanceError('')
    setProvenanceLoading(admin)
    if (admin) {
      void getCustomerProvenance(customer)
        .then((result) => { if (requestId === provenanceRequestId.current) setProvenance(result) })
        .catch((cause) => { if (requestId === provenanceRequestId.current) setProvenanceError(cause instanceof Error ? cause.message : 'Kaynak bilgisi okunamadı.') })
        .finally(() => { if (requestId === provenanceRequestId.current) setProvenanceLoading(false) })
    }
  }
  const closeDrawer = useCallback(() => {
    ++provenanceRequestId.current
    setDrawerCustomer(null)
    setProvenance(null)
    setProvenanceLoading(false)
    setProvenanceError('')
    window.setTimeout(() => triggerRef.current?.focus(), 0)
  }, [])
  function drillToCustomers(chief: string | null, representative: string | null) {
    setFilters((current) => ({ ...current, chief: chief ?? '', representative: representative ?? '' }))
    setPage(0)
    setView('customers')
  }
  function drillToOrganization(customer: CustomerRecord) {
    if (!customer.chief || !customer.representative) return
    setOrgSelection({ chief: customer.chief, representative: customer.representative })
    setView('organization')
  }

  const pages = Math.max(1, Math.ceil(customerPage.count / PAGE_SIZE))
  const activeFilterCount = Object.values(filters).filter(Boolean).length

  return <section className="customer-workspace-v7">
    <header className="customer-page-head-v7">
      <div>
        <p className="customer-eyebrow-v7">PACKAGE {releasePackage} · MÜŞTERİ MASTER</p>
        <h1 id="page-title">Müşteri portföyü</h1>
        <p>Resolved müşteri evrenini bulun, filtreleyin ve satış organizasyonu içindeki bağlamını görün.</p>
      </div>
      <span className="customer-freshness-v7"><i aria-hidden="true" /> Güncel yayın yüzeyi</span>
    </header>

    <div className="workspace-tabs-v7" role="tablist" aria-label="Müşteri çalışma alanı">
      <button type="button" role="tab" aria-selected={view === 'customers'} className={view === 'customers' ? 'active' : ''} onClick={() => setView('customers')}>Müşteriler</button>
      <button type="button" role="tab" aria-selected={view === 'organization'} className={view === 'organization' ? 'active' : ''} onClick={() => setView('organization')}>Organizasyon</button>
    </div>

    {view === 'customers' ? <CustomerList
      filters={filters}
      onFilter={updateFilter}
      onClear={clearFilters}
      customerPage={customerPage}
      allCustomers={allCustomers}
      allLoading={allLoading}
      filterOptions={filterOptions}
      filterOptionsError={filterOptionsError}
      loading={loading}
      error={customerError}
      pages={pages}
      page={page}
      setPage={setPage}
      sort={sort}
      setSort={setSort}
      onOpen={openDrawer}
      onCopy={copyCustomerId}
      mobileFiltersOpen={mobileFiltersOpen}
      setMobileFiltersOpen={setMobileFiltersOpen}
      activeFilterCount={activeFilterCount}
    /> : <OrganizationView
      customers={organizationCustomers}
      loading={allLoading}
      error={organizationError}
      chiefs={chiefs}
      selection={orgSelection}
      setSelection={setOrgSelection}
      onDrill={drillToCustomers}
    />}

    {drawerCustomer ? <CustomerDrawer
      admin={admin}
      customer={drawerCustomer}
      provenance={provenance}
      provenanceLoading={provenanceLoading}
      provenanceError={provenanceError}
      onClose={closeDrawer}
      onCopy={copyCustomerId}
      onOrganization={() => { closeDrawer(); drillToOrganization(drawerCustomer) }}
    /> : null}
    {toast ? <div className="customer-toast-v7" role="status">{toast}</div> : null}
  </section>
}

function CustomerList(props: {
  filters: CustomerFilters
  onFilter: (key: keyof CustomerFilters, value: string) => void
  onClear: () => void
  customerPage: { rows: CustomerRecord[]; count: number }
  allCustomers: CustomerRecord[]
  allLoading: boolean
  filterOptions: CustomerFilterOptions | null
  filterOptionsError: string
  loading: boolean
  error: string
  pages: number
  page: number
  setPage: (page: number) => void
  sort: CustomerSort
  setSort: (sort: CustomerSort) => void
  onOpen: (customer: CustomerRecord, trigger?: HTMLElement | null) => void
  onCopy: (id: string) => void
  mobileFiltersOpen: boolean
  setMobileFiltersOpen: (open: boolean) => void
  activeFilterCount: number
}) {
  const {
    filters, onFilter, onClear, customerPage, allCustomers, allLoading, filterOptions, filterOptionsError,
    loading, error, pages, page, setPage, sort, setSort, onOpen, onCopy, mobileFiltersOpen, setMobileFiltersOpen,
    activeFilterCount,
  } = props
  const activeCount = allCustomers.filter((customer) => customer.status === 'ACTIVE').length
  const organizedCount = allCustomers.filter((customer) => customer.status === 'ACTIVE' && customer.representative && customer.chief).length
  const openCount = allCustomers.filter((customer) => customer.channel === 'OPEN').length

  function toggleSort(key: CustomerSortKey) {
    setPage(0)
    setSort(sort.key === key ? { key, ascending: !sort.ascending } : { key, ascending: true })
  }
  function sortGlyph(key: CustomerSortKey) { return sort.key === key ? (sort.ascending ? ' ↑' : ' ↓') : '' }
  function handleRowKey(event: KeyboardEvent<HTMLTableRowElement>, customer: CustomerRecord) {
    if ((event.target as HTMLElement).closest('button')) return
    if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onOpen(customer, event.currentTarget) }
  }

  return <>
    <section className="customer-summary-v7" aria-label="Müşteri portföyü özeti">
      <article className="customer-summary-card-v7 primary"><span>Toplam yayımlanmış müşteri</span><strong>{allLoading ? '—' : allCustomers.length.toLocaleString('tr-TR')}</strong><small>Current business read surface</small></article>
      <article className="customer-summary-card-v7"><span>Aktif müşteri</span><strong>{allLoading ? '—' : activeCount.toLocaleString('tr-TR')}</strong><small>Resolved durum</small></article>
      <article className="customer-summary-card-v7"><span>Organizasyona bağlı</span><strong>{allLoading ? '—' : organizedCount.toLocaleString('tr-TR')}</strong><small>%90 kuralıyla çözümlenmiş hiyerarşi</small></article>
      <article className="customer-summary-card-v7"><span>Açık Kanal</span><strong>{allLoading ? '—' : openCount.toLocaleString('tr-TR')}</strong><small>Yayımlanmış müşteri evreni</small></article>
    </section>

    <section className="customer-list-surface-v7">
      <div className="customer-list-head-v7">
        <div><strong>Resolved customer listesi</strong><span>Müşteri no, tabela, müşteri veya temsilci ile hızlı arama.</span></div>
        <div className="customer-search-actions-v7">
          <label className="customer-search-v7"><span aria-hidden="true">⌕</span><input value={filters.search} onChange={(event) => onFilter('search', event.target.value)} placeholder="Müşteri no, ad, tabela ara…" /></label>
          <button type="button" className="mobile-filter-button-v7" onClick={() => setMobileFiltersOpen(true)}>Filtreler <b>{activeFilterCount}</b></button>
        </div>
      </div>

      <div className={`customer-filter-panel-v7 ${mobileFiltersOpen ? 'mobile-open' : ''}`}>
        <div className="mobile-filter-head-v7"><div><strong>Filtreler</strong><span>Sonuçları daraltın</span></div><button type="button" aria-label="Filtreleri kapat" onClick={() => setMobileFiltersOpen(false)}>×</button></div>
        <FilterSelect label="Durum" value={filters.status} values={filterOptions?.status ?? []} displayValue={statusLabel} onChange={(value) => onFilter('status', value)} />
        <FilterSelect label="Satış Kanalı" value={filters.channel} values={filterOptions?.channel ?? []} displayValue={channelLabel} onChange={(value) => onFilter('channel', value)} />
        <FilterSelect label="Segment" value={filters.segment} values={filterOptions?.segment ?? []} onChange={(value) => onFilter('segment', value)} />
        <FilterSelect label="Satış Temsilcisi" value={filters.representative} values={filterOptions?.representative ?? []} displayValue={personName} onChange={(value) => onFilter('representative', value)} />
        <FilterSelect label="Satış Şefi" value={filters.chief} values={filterOptions?.chief ?? []} displayValue={personName} onChange={(value) => onFilter('chief', value)} />
        <div className="filter-actions-v7"><button type="button" onClick={onClear}>Temizle</button><button type="button" className="primary" onClick={() => setMobileFiltersOpen(false)}>Sonuçları göster</button></div>
      </div>
      {mobileFiltersOpen ? <button className="mobile-filter-backdrop-v7" type="button" aria-label="Filtreleri kapat" onClick={() => setMobileFiltersOpen(false)} /> : null}

      <ActiveFilterChips filters={filters} onFilter={onFilter} />
      {filterOptionsError ? <div className="customer-notice-v7 warning">Filtre seçenekleri eksik olabilir. {filterOptionsError}</div> : null}
      {error ? <div className="customer-notice-v7 error" role="alert">Müşteri verisi okunamadı. {error}</div> : null}
      {loading ? <div className="customer-loading-v7" role="status"><i /> Müşteriler yükleniyor…</div> : null}

      <div className="customer-result-bar-v7"><strong>{customerPage.count.toLocaleString('tr-TR')} kayıt</strong><span>Sayfa başına {PAGE_SIZE}</span></div>

      <div className="customer-table-wrap-v7">
        <table className="customer-table-v7">
          <thead><tr>
            <th><button type="button" onClick={() => toggleSort('customerId')}>Müşteri No{sortGlyph('customerId')}</button></th>
            <th><button type="button" onClick={() => toggleSort('tradeName')}>Tabela{sortGlyph('tradeName')}</button></th>
            <th><button type="button" onClick={() => toggleSort('customerName')}>Müşteri{sortGlyph('customerName')}</button></th>
            <th><button type="button" onClick={() => toggleSort('channel')}>Satış Kanalı{sortGlyph('channel')}</button></th>
            <th><button type="button" onClick={() => toggleSort('segment')}>Segment{sortGlyph('segment')}</button></th>
            <th><button type="button" onClick={() => toggleSort('representative')}>Satış Temsilcisi{sortGlyph('representative')}</button></th>
            <th><button type="button" onClick={() => toggleSort('chief')}>Satış Şefi{sortGlyph('chief')}</button></th>
            <th><button type="button" onClick={() => toggleSort('status')}>Durum{sortGlyph('status')}</button></th>
          </tr></thead>
          <tbody>{customerPage.rows.map((customer) => <tr key={customer.customerId} tabIndex={0} role="button" aria-label={`${display(customer.tradeName)} müşteri detayını aç`} onClick={(event) => { if ((event.target as HTMLElement).closest('button')) return; onOpen(customer, event.currentTarget) }} onKeyDown={(event) => handleRowKey(event, customer)}>
            <td className="customer-id-sticky-v7"><button className="copy-customer-id-v7" type="button" onClick={(event) => { event.stopPropagation(); onCopy(customer.customerId) }}>{customer.customerId}</button></td>
            <td><strong className="table-trade-v7" title={display(customer.tradeName)}>{display(customer.tradeName)}</strong></td>
            <td><div className="customer-name-v7"><span>{initials(customer.customerName)}</span><strong title={display(customer.customerName)}>{display(customer.customerName)}</strong></div></td>
            <td><ChannelBadge channel={customer.channel} /></td>
            <td><span className="segment-badge-v7">{display(customer.segment)}</span></td>
            <td><PersonCell value={customer.representative} /></td>
            <td><strong className="chief-name-v7">{personName(customer.chief)}</strong></td>
            <td><StatusBadge status={customer.status} /></td>
          </tr>)}</tbody>
        </table>
        {!loading && !customerPage.rows.length ? <div className="customer-empty-v7"><span>⌕</span><strong>Eşleşen müşteri bulunamadı.</strong><small>Arama veya filtreleri temizleyip tekrar deneyin.</small></div> : null}
      </div>

      <div className="customer-mobile-list-v7">{customerPage.rows.map((customer) => <article key={customer.customerId} className="customer-mobile-card-v7" tabIndex={0} role="button" onClick={(event) => { if ((event.target as HTMLElement).closest('button')) return; onOpen(customer, event.currentTarget) }} onKeyDown={(event) => { if ((event.target as HTMLElement).closest('button')) return; if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); onOpen(customer, event.currentTarget) } }}>
        <div className="mobile-card-head-v7"><button type="button" onClick={(event) => { event.stopPropagation(); onCopy(customer.customerId) }}>{customer.customerId}</button><StatusBadge status={customer.status} /></div>
        <h3>{display(customer.tradeName)}</h3>
        <p>{display(customer.customerName)}</p>
        <div className="mobile-card-facts-v7"><div><span>Satış Kanalı</span><ChannelBadge channel={customer.channel} /></div><div><span>Segment</span><strong>{display(customer.segment)}</strong></div></div>
        <div className="mobile-representative-v7"><span>Satış Temsilcisi</span><strong>{personName(customer.representative)}</strong></div>
        <div className="mobile-card-foot-v7"><span>Detayda satış şefi ve tüm alanlar</span><button type="button" onClick={(event) => { event.stopPropagation(); onOpen(customer, event.currentTarget) }}>Detay ›</button></div>
      </article>)}</div>

      <div className="customer-pagination-v7"><span>{page + 1} / {pages} sayfa</span><div><button type="button" disabled={page === 0} onClick={() => setPage(Math.max(0, page - 1))}>‹ Önceki</button><button type="button" disabled={page + 1 >= pages} onClick={() => setPage(Math.min(pages - 1, page + 1))}>Sonraki ›</button></div></div>
    </section>
  </>
}

function FilterSelect({ label, value, values, onChange, displayValue = (item: string) => item }: { label: string; value: string; values: string[]; onChange: (value: string) => void; displayValue?: (value: string) => string }) {
  return <label className="customer-filter-v7"><span>{label}</span><select value={value} onChange={(event) => onChange(event.target.value)}><option value="">Tümü</option>{values.map((item) => <option key={item} value={item}>{displayValue(item)}</option>)}</select></label>
}

function ActiveFilterChips({ filters, onFilter }: { filters: CustomerFilters; onFilter: (key: keyof CustomerFilters, value: string) => void }) {
  const labels: Record<keyof CustomerFilters, string> = { search: 'Arama', status: 'Durum', channel: 'Satış Kanalı', segment: 'Segment', representative: 'Satış Temsilcisi', chief: 'Satış Şefi' }
  const items = (Object.entries(filters) as [keyof CustomerFilters, string][]).filter(([, value]) => Boolean(value))
  if (!items.length) return null
  const renderValue = (key: keyof CustomerFilters, value: string) => key === 'status' ? statusLabel(value) : key === 'channel' ? channelLabel(value) : key === 'representative' || key === 'chief' ? personName(value) : value
  return <div className="active-filter-row-v7"><span>Aktif filtreler</span><div>{items.map(([key, value]) => <button type="button" key={key} onClick={() => onFilter(key, '')}>{labels[key]}: {renderValue(key, value)} <b>×</b></button>)}</div></div>
}

function ChannelBadge({ channel }: { channel: string }) { return <span className={`channel-badge-v7 ${channelClass(channel)}`}><i />{channelLabel(channel)}</span> }
function StatusBadge({ status }: { status: string }) { return <span className={`status-badge-v7 ${statusClass(status)}`}>{statusLabel(status)}</span> }
function PersonCell({ value }: { value: string | null }) { return <div className="person-cell-v7"><span>{initials(personName(value))}</span><strong title={personName(value)}>{personName(value)}</strong></div> }

function OrganizationView({ customers, loading, error, chiefs, selection, setSelection, onDrill }: {
  customers: CustomerRecord[]
  loading: boolean
  error: string
  chiefs: string[]
  selection: OrgSelection
  setSelection: (selection: OrgSelection) => void
  onDrill: (chief: string | null, representative: string | null) => void
}) {
  if (loading) return <div className="customer-state-v7" role="status">Organizasyon verisi yükleniyor…</div>
  if (error) return <div className="customer-notice-v7 error" role="alert">Organizasyon verisi yüklenemedi. {error}</div>
  if (!customers.length || !selection.chief) return <div className="customer-state-v7"><strong>Çözülmüş organizasyon eşleşmesi bulunmuyor.</strong></div>

  const chiefCustomers = customers.filter((customer) => customer.chief === selection.chief)
  const reps = [...new Set(chiefCustomers.map((customer) => customer.representative).filter((value): value is string => Boolean(value)))].sort((a, b) => personName(a).localeCompare(personName(b), 'tr'))
  const selectedCustomers = selection.representative ? chiefCustomers.filter((customer) => customer.representative === selection.representative) : chiefCustomers
  const channelCounts = new Map(counts(selectedCustomers.map((customer) => customer.channel)))
  const open = channelCounts.get('OPEN') ?? 0
  const closed = channelCounts.get('CLOSED') ?? 0
  const openPct = selectedCustomers.length ? Math.round(open / selectedCustomers.length * 100) : 0
  const segmentCounts = counts(selectedCustomers.map((customer) => customer.segment).filter((value): value is string => Boolean(value)))
  const maxSegment = Math.max(1, ...segmentCounts.map(([, value]) => value))
  const selectedName = selection.representative ?? selection.chief

  return <section className="organization-v7">
    <header className="organization-head-v7"><div><span>SATIŞ ORGANİZASYONU</span><h2>Şef ve temsilci portföyleri</h2><p>%90 kuralıyla çözümlenmiş authoritative organizasyonu müşteri dağılımlarıyla inceleyin.</p></div><div><small>Çözümlenmiş organizasyon</small><strong>{new Set(customers.map((customer) => customer.representative)).size} temsilci · {customers.length.toLocaleString('tr-TR')} aktif müşteri</strong></div></header>

    <div className="chief-switcher-v7">{chiefs.map((chief) => {
      const rows = customers.filter((customer) => customer.chief === chief)
      const repCount = new Set(rows.map((customer) => customer.representative)).size
      return <button key={chief} type="button" className={selection.chief === chief ? 'active' : ''} onClick={() => setSelection({ chief, representative: null })}><span>{initials(personName(chief))}</span><div><strong>{personName(chief)}</strong><small>{repCount} temsilci · {rows.length} aktif müşteri</small></div><b>›</b></button>
    })}</div>

    <div className="organization-scope-v7"><span>Seçili kapsam</span><strong>{personName(selection.chief)}</strong><b>›</b><strong>{selection.representative ? personName(selection.representative) : 'Tüm temsilciler'}</strong><em>{selectedCustomers.length} aktif müşteri</em></div>

    <div className="organization-overview-v7">
      <article className="organization-spotlight-v7"><div className="spotlight-head-v7"><div className="spotlight-person-v7"><span>{initials(personName(selectedName))}</span><div><small>{selection.representative ? 'Satış Temsilcisi' : 'Satış Şefi'}</small><h3>{personName(selectedName)}</h3><p>{selection.representative ? `${personName(selection.chief)} ekibi · temsilci portföyü` : `${reps.length} satış temsilcisi`}</p></div></div><button type="button" onClick={() => onDrill(selection.chief, selection.representative)}>{selection.representative ? 'Temsilci müşterileri' : 'Şef müşterileri'} ↗</button></div><div className="spotlight-metrics-v7"><div><span>Aktif müşteri</span><strong>{selectedCustomers.length}</strong></div><div><span>Açık Kanal</span><strong>{open}</strong></div><div><span>Kapalı Kanal</span><strong>{closed}</strong></div></div></article>

      <article className="organization-channel-v7"><header><strong>Satış kanalı dağılımı</strong><span>Aktif müşteri portföyü</span></header><div className="donut-row-v7"><div className="donut-v7" style={{ '--open-pct': `${openPct}%` } as CSSProperties}><div><strong>{openPct}%</strong><span>Açık</span></div></div><div className="channel-legend-v7"><div><i className="open" /><span>Açık Kanal</span><strong>{open}</strong></div><div><i className="closed" /><span>Kapalı Kanal</span><strong>{closed}</strong></div></div></div></article>

      <article className="organization-segment-v7"><header><strong>Segment dağılımı</strong><span>Müşteri hacim segmenti</span></header><div className="segment-bars-v7">{segmentCounts.map(([label, value]) => <div key={label}><span>{label}</span><i><b style={{ width: `${Math.round(value / maxSegment * 100)}%` }} /></i><strong>{value}</strong></div>)}</div></article>
    </div>

    <section className="representative-roster-v7"><header><div><span>EKİP</span><h3>Satış temsilcileri</h3><p>Bir temsilci seçin; üstteki kanal ve segment analizi seçilen portföye göre güncellensin.</p></div><strong>{reps.length} temsilci</strong></header><div>{reps.map((rep) => {
      const rows = chiefCustomers.filter((customer) => customer.representative === rep)
      const selected = selection.representative === rep
      return <div key={rep} className={`representative-row-v7 ${selected ? 'selected' : ''}`} role="button" tabIndex={0} aria-pressed={selected} onClick={(event) => { if ((event.target as HTMLElement).closest('button')) return; setSelection({ chief: selection.chief, representative: selected ? null : rep }) }} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); setSelection({ chief: selection.chief, representative: selected ? null : rep }) } }}>
        <div className="representative-identity-v7"><span className="representative-person-icon-v7" aria-hidden="true"><PersonIcon /></span><div><small>SATIŞ TEMSİLCİSİ</small><strong>{personName(rep)}</strong></div></div>
        <div className="representative-count-v7"><strong>{rows.length}</strong><span>aktif müşteri</span></div>
        <span className="representative-state-v7">{selected ? '✓ Seçili' : 'Dağılımı gör'}</span>
        <button type="button" onClick={() => onDrill(selection.chief, rep)}>Müşterileri aç ↗</button>
      </div>
    })}</div></section>
  </section>
}

function PersonIcon() { return <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Z"/><path d="M4.5 20c.8-4 3.2-6 7.5-6s6.7 2 7.5 6"/></svg> }

function CustomerDrawer({ admin, customer, provenance, provenanceLoading, provenanceError, onClose, onCopy, onOrganization }: {
  admin: boolean
  customer: CustomerRecord
  provenance: CustomerProvenance | null
  provenanceLoading: boolean
  provenanceError: string
  onClose: () => void
  onCopy: (id: string) => void
  onOrganization: () => void
}) {
  const drawerRef = useRef<HTMLElement>(null)
  useEffect(() => {
    const drawer = drawerRef.current
    if (!drawer) return
    const scrollY = window.scrollY
    const previous = { position: document.body.style.position, top: document.body.style.top, left: document.body.style.left, right: document.body.style.right, width: document.body.style.width, overflow: document.body.style.overflow }
    document.body.classList.add('customer-drawer-scroll-locked')
    document.body.style.position = 'fixed'
    document.body.style.top = `-${scrollY}px`
    document.body.style.left = '0'
    document.body.style.right = '0'
    document.body.style.width = '100%'
    document.body.style.overflow = 'hidden'

    const focusable = () => [...drawer.querySelectorAll<HTMLElement>('button, summary, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])')]
    focusable()[0]?.focus()
    const onKey = (event: globalThis.KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
      if (event.key !== 'Tab') return
      const items = focusable()
      if (!items.length) return
      const first = items[0]
      const last = items[items.length - 1]
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus() }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus() }
    }
    drawer.addEventListener('keydown', onKey)
    return () => {
      drawer.removeEventListener('keydown', onKey)
      document.body.classList.remove('customer-drawer-scroll-locked')
      Object.assign(document.body.style, previous)
      window.scrollTo(0, scrollY)
    }
  }, [onClose])

  return <>
    <button className="customer-drawer-backdrop-v7" type="button" aria-label="Müşteri detayını kapat" onClick={onClose} />
    <aside ref={drawerRef} className="customer-drawer-v7" role="dialog" aria-modal="true" aria-labelledby="customer-drawer-title-v7">
      <div className="drawer-topbar-v7"><div><span>RESOLVED MÜŞTERİ</span><strong>Portföy detayı</strong></div><button type="button" aria-label="Müşteri detayını kapat" onClick={onClose}>×</button></div>
      <div className="drawer-body-v7">
        <section className="drawer-hero-v7">
          <div className="drawer-hero-head-v7"><div><span>Tabela</span><h2 id="customer-drawer-title-v7">{display(customer.tradeName)}</h2><p>{display(customer.customerName)}</p></div><em>● LIVE</em></div>
          <div className="drawer-badges-v7"><StatusBadge status={customer.status} /><ChannelBadge channel={customer.channel} /><span className="drawer-segment-v7">{display(customer.segment)}</span></div>
          <div className="drawer-number-v7"><span>Müşteri No</span><strong>{customer.customerId}</strong><button type="button" onClick={() => onCopy(customer.customerId)}>Kopyala</button></div>
        </section>

        <section className="drawer-section-v7"><header><span>ORGANİZASYON</span><h3>Bu müşteri kime bağlı?</h3></header><div className="drawer-org-chain-v7"><div className="chief"><span>Satış Şefi</span><strong>{personName(customer.chief)}</strong></div><b>›</b><div className="rep"><span>Satış Temsilcisi</span><strong>{personName(customer.representative)}</strong></div><b>›</b><div><span>Müşteri</span><strong>{display(customer.tradeName)}</strong></div></div>{customer.chief && customer.representative ? <button className="drawer-org-action-v7" type="button" onClick={onOrganization}>Organizasyonda aç ↗</button> : null}</section>

        <section className="drawer-section-v7"><header><span>HIZLI BAKIŞ</span><h3>Müşteri sınıflandırması</h3></header><div className="drawer-facts-v7"><article><span>Durum</span><strong>{statusLabel(customer.status)}</strong></article><article><span>Satış Kanalı</span><strong>{channelLabel(customer.channel)}</strong></article><article><span>Segment</span><strong>{display(customer.segment)}</strong></article><article><span>Satış Temsilcisi</span><strong>{personName(customer.representative)}</strong></article></div></section>

        {admin ? <details className="drawer-provenance-v7"><summary><span><b>Kaynak & provenance</b><small>Teknik izleme bilgileri</small></span><em>⌄</em></summary><div>{provenanceLoading ? <p>Kaynak bilgisi yükleniyor…</p> : provenanceError ? <p className="error">Kaynak bilgisi okunamadı. {provenanceError}</p> : provenance ? <div className="provenance-grid-v7"><ProvenanceTile label="Snapshot" value={provenance.snapshotId} /><ProvenanceTile label="Source batch" value={provenance.batchId} /><ProvenanceTile label="Contract" value={provenance.contract} /><ProvenanceTile label="Publication" value={`${provenance.status}${provenance.matched ? ' / MATCHED' : ''}`} /></div> : <p>Kaynak bilgisi bulunamadı.</p>}</div></details> : null}
        <p className="drawer-readonly-v7">Bu yüzey read-only müşteri keşfi içindir; manuel müşteri düzenleme akışı içermez.</p>
      </div>
    </aside>
  </>
}

function ProvenanceTile({ label, value }: { label: string; value: ReactNode }) { return <article><span>{label}</span><strong>{value}</strong></article> }
