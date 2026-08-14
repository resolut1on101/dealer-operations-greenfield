import { useCallback, useEffect, useMemo, useRef, useState, type Dispatch, type KeyboardEvent, type SetStateAction } from 'react'
import type { ApplicationRole, WarehouseStockBusinessRow, WarehouseStockUiSummary } from '@dealer-operations/contracts'
import { releasePackage } from './lib/environment'
import {
  filterWarehouseStockRows,
  loadWarehouseStockWorkspace,
  requiresLargeLpuConfirmation,
  saveWarehouseStockLpuUpdates,
  sortWarehouseStockRows,
  type WarehouseStockLitreFilter,
  type WarehouseStockSort,
} from './lib/warehouse-stock-api'

const initialSort: WarehouseStockSort = { key: 'productName', ascending: true }

function formatNumber(value: number, fractionDigits = 2) {
  return new Intl.NumberFormat('tr-TR', { minimumFractionDigits: fractionDigits, maximumFractionDigits: fractionDigits }).format(value)
}
function formatLpu(value: number) { return new Intl.NumberFormat('tr-TR', { minimumFractionDigits: 3, maximumFractionDigits: 3 }).format(value) }
function formatPublication(value: string) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? '—' : new Intl.DateTimeFormat('tr-TR', { dateStyle: 'short', timeStyle: 'short' }).format(date)
}
function productName(row: WarehouseStockBusinessRow) { return row.productName?.trim() || `Ürün ${row.productCode}` }

export function WarehouseStockWorkspace({ role }: { role: ApplicationRole }) {
  const admin = role === 'admin'
  const [summary, setSummary] = useState<WarehouseStockUiSummary | null>(null)
  const [rows, setRows] = useState<WarehouseStockBusinessRow[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [litreFilter, setLitreFilter] = useState<WarehouseStockLitreFilter>('all')
  const [sort, setSort] = useState<WarehouseStockSort>(initialSort)
  const [drawerRow, setDrawerRow] = useState<WarehouseStockBusinessRow | null>(null)
  const [missingOpen, setMissingOpen] = useState(false)
  const [missingDrafts, setMissingDrafts] = useState<Record<string, string>>({})
  const [savingMissing, setSavingMissing] = useState(false)
  const [toast, setToast] = useState('')
  const requestId = useRef(0)
  const triggerRef = useRef<HTMLElement | null>(null)

  const refresh = useCallback(async () => {
    const id = ++requestId.current
    setLoading(true); setError('')
    try {
      const result = await loadWarehouseStockWorkspace()
      if (id !== requestId.current) return
      setSummary(result.summary); setRows(result.rows)
      setDrawerRow((current) => current ? result.rows.find((row) => row.productCode === current.productCode) ?? null : null)
    } catch (cause) {
      if (id === requestId.current) setError(cause instanceof Error ? cause.message : 'Depo stoku okunamadı.')
    } finally { if (id === requestId.current) setLoading(false) }
  }, [])
  useEffect(() => { void refresh() }, [refresh])

  const visibleRows = useMemo(() => sortWarehouseStockRows(filterWarehouseStockRows(rows, search, litreFilter), sort), [litreFilter, rows, search, sort])
  const missingRows = useMemo(() => rows.filter((row) => row.litreResolutionState === 'PARTIAL'), [rows])

  function notify(message: string) { setToast(message); window.setTimeout(() => setToast(''), 1800) }
  function toggleSort(key: WarehouseStockSort['key']) { setSort((current) => current.key === key ? { key, ascending: !current.ascending } : { key, ascending: true }) }
  function sortGlyph(key: WarehouseStockSort['key']) { return sort.key === key ? (sort.ascending ? '↑' : '↓') : '↕' }
  function openDrawer(row: WarehouseStockBusinessRow, trigger?: HTMLElement | null) { triggerRef.current = trigger ?? document.activeElement as HTMLElement; setDrawerRow(row) }
  const closeDrawer = useCallback(() => { setDrawerRow(null); window.setTimeout(() => triggerRef.current?.focus(), 0) }, [])
  function handleRowKey(event: KeyboardEvent<HTMLTableRowElement>, row: WarehouseStockBusinessRow) {
    if ((event.target as HTMLElement).closest('button')) return
    if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); openDrawer(row, event.currentTarget) }
  }
  function openMissing() {
    const drafts: Record<string, string> = {}
    missingRows.forEach((row) => { drafts[row.productCode] = '' })
    setMissingDrafts(drafts); setMissingOpen(true)
  }
  async function saveMissing() {
    if (!summary) return
    const updates = missingRows.flatMap((row) => {
      const raw = (missingDrafts[row.productCode] ?? '').trim().replace(',', '.')
      if (!raw) return []
      const lpu = Number(raw)
      return Number.isFinite(lpu) && lpu > 0 ? [{ productCode: row.productCode, lpu }] : []
    })
    if (!updates.length) { notify('Kaydedilecek geçerli Litre / Birim değeri yok.'); return }
    setSavingMissing(true)
    try {
      const result = await saveWarehouseStockLpuUpdates(summary.scopeKey, updates)
      notify(`${result.updatedCount} ürünün Litre / Birim bilgisi kaydedildi.`)
      await refresh()
      if (result.remainingMissingCount === 0) setMissingOpen(false)
    } catch (cause) { notify(cause instanceof Error ? cause.message : 'Litre / Birim bilgisi kaydedilemedi.') }
    finally { setSavingMissing(false) }
  }

  return <section className="warehouse-workspace-v1">
    <header className="warehouse-page-head-v1">
      <div><p className="warehouse-eyebrow-v1">PACKAGE {releasePackage} · ANLIK DEPO STOKU</p><h1 id="page-title">Depo Stoku</h1><p>En son başarılı Malzemeler yayınının güncel depo stok durumunu gösterir. Yeni başarılı yayın, mevcut snapshot’ın tamamının yerini alır.</p><div className="warehouse-meta-v1"><span>Son yayın <b>{summary ? formatPublication(summary.sourcePublishedAt) : '—'}</b></span><span>Kaynak <b>WAREHOUSE_STOCK v1</b></span><span>Semantik <b>FULL_REPLACE</b></span></div></div>
      <button className="warehouse-refresh-v1" type="button" onClick={() => void refresh()} disabled={loading}>↻ {loading ? 'Yükleniyor…' : 'Yenile'}</button>
    </header>

    {admin && summary && summary.litrePartialCount > 0 ? <section className="warehouse-lpu-alert-v1" role="status"><div><i aria-hidden="true">!</i><span><strong>{summary.litrePartialCount} ürünün Litre / Birim bilgisi eksik</strong><small>Eksik ürünler için Toplam Litre üretilmez. Bildiğiniz değerleri toplu olarak tanımlayabilirsiniz.</small></span></div><button type="button" onClick={openMissing}>Tanımla</button></section> : null}

    <section className="warehouse-kpis-v1" aria-label="Depo stoku özeti">
      <article className="warehouse-kpi-v1 primary"><span>Toplam Litre</span><strong>{summary?.totalAvailableLitres === null || summary?.totalAvailableLitres === undefined ? '—' : formatNumber(summary.totalAvailableLitres)}{summary?.totalAvailableLitres === null || summary?.totalAvailableLitres === undefined ? null : <small> Lt</small>}</strong></article>
      <article className="warehouse-kpi-v1"><span>Toplam Ürün</span><strong>{summary ? summary.businessRowCount.toLocaleString('tr-TR') : '—'}</strong></article>
    </section>

    <section className="warehouse-list-surface-v1">
      <div className="warehouse-toolbar-v1"><label className="warehouse-search-v1"><span aria-hidden="true">⌕</span><input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Ürün adı veya ürün kodu ile ara…" /></label><label className="warehouse-filter-v1"><span>Litre Durumu</span><select value={litreFilter} onChange={(event) => setLitreFilter(event.target.value as WarehouseStockLitreFilter)}><option value="all">Tümü</option><option value="resolved">Hesaplanan</option><option value="partial">Eksik</option></select></label></div>
      {error ? <div className="warehouse-notice-v1 error" role="alert">Depo stoku okunamadı. {error}</div> : null}
      {loading ? <div className="warehouse-loading-v1" role="status"><i /> Stok verisi yükleniyor…</div> : null}
      {!loading && !error && visibleRows.length === 0 ? <div className="warehouse-empty-v1"><strong>Sonuç bulunamadı.</strong><span>Arama veya Litre Durumu filtresini değiştirin.</span></div> : null}

      <div className="warehouse-table-wrap-v1"><table className="warehouse-table-v1"><thead><tr><th>Ürün Kodu</th><th><button type="button" onClick={() => toggleSort('productName')}>Ürün Adı <b>{sortGlyph('productName')}</b></button></th><th className="numeric"><button type="button" onClick={() => toggleSort('stock')}>Stok <b>{sortGlyph('stock')}</b></button></th><th className="numeric">Litre / Birim</th><th className="numeric"><button type="button" onClick={() => toggleSort('totalLitres')}>Toplam Litre <b>{sortGlyph('totalLitres')}</b></button></th><th aria-label="Detay" /></tr></thead><tbody>{visibleRows.map((row) => <tr key={row.productCode} tabIndex={0} className={drawerRow?.productCode === row.productCode ? 'selected' : ''} onClick={(event) => { if ((event.target as HTMLElement).closest('button')) return; openDrawer(row, event.currentTarget) }} onKeyDown={(event) => handleRowKey(event, row)}><td><span className="warehouse-code-v1">{row.productCode}</span></td><td className="warehouse-product-v1"><strong title={productName(row)}>{productName(row)}</strong></td><td className="numeric"><strong>{formatNumber(row.exactAvailableQuantity)}</strong></td><td className="numeric">{row.lpu === null ? <span className="warehouse-missing-v1">! Eksik</span> : <strong>{formatLpu(row.lpu)}</strong>}</td><td className="numeric warehouse-litres-v1">{row.availableLitres === null ? <span className="warehouse-missing-v1">— <small>Litre / Birim eksik</small></span> : <strong>{formatNumber(row.availableLitres)} <small>Lt</small></strong>}</td><td className="warehouse-row-action-v1"><button type="button" aria-label={`${productName(row)} detayını aç`} onClick={(event) => { event.stopPropagation(); openDrawer(row, event.currentTarget) }}>›</button></td></tr>)}</tbody></table></div>

      <div className="warehouse-mobile-list-v1">{visibleRows.map((row) => <article key={row.productCode} className="warehouse-mobile-card-v1" role="button" tabIndex={0} onClick={(event) => { if ((event.target as HTMLElement).closest('button')) return; openDrawer(row, event.currentTarget) }} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); openDrawer(row, event.currentTarget) } }}><h3>{productName(row)}</h3><code>{row.productCode}</code><div className="warehouse-mobile-top-facts-v1"><div><span>Stok</span><strong>{formatNumber(row.exactAvailableQuantity)}</strong></div><div><span>Litre / Birim</span><strong>{row.lpu === null ? '—' : formatLpu(row.lpu)}</strong></div></div><div className="warehouse-mobile-litres-v1"><span>Toplam Litre</span><strong>{row.availableLitres === null ? '—' : formatNumber(row.availableLitres)}{row.availableLitres === null ? null : <small> Lt</small>}</strong></div></article>)}</div>
    </section>

    {drawerRow && summary ? <WarehouseDrawer admin={admin} row={drawerRow} scopeKey={summary.scopeKey} onClose={closeDrawer} onSaved={async () => { await refresh(); notify('Litre / Birim güncellendi.') }} /> : null}
    {missingOpen ? <MissingLpuModal rows={missingRows} drafts={missingDrafts} setDrafts={setMissingDrafts} saving={savingMissing} onClose={() => setMissingOpen(false)} onSave={() => void saveMissing()} /> : null}
    {toast ? <div className="customer-toast-v7" role="status">{toast}</div> : null}
  </section>
}

function WarehouseDrawer({ admin, row, scopeKey, onClose, onSaved }: { admin: boolean; row: WarehouseStockBusinessRow; scopeKey: string; onClose: () => void; onSaved: () => Promise<void> }) {
  const ref = useRef<HTMLElement>(null)
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState(row.lpu === null ? '' : String(row.lpu))
  const [saving, setSaving] = useState(false)
  const [confirmValue, setConfirmValue] = useState<number | null>(null)
  const [error, setError] = useState('')
  useEffect(() => { setDraft(row.lpu === null ? '' : String(row.lpu)); setEditing(false); setError('') }, [row])
  useEffect(() => {
    const drawer = ref.current; if (!drawer) return
    const scrollY = window.scrollY
    const previous = { position: document.body.style.position, top: document.body.style.top, left: document.body.style.left, right: document.body.style.right, width: document.body.style.width, overflow: document.body.style.overflow }
    document.body.classList.add('customer-drawer-scroll-locked'); document.body.style.position = 'fixed'; document.body.style.top = `-${scrollY}px`; document.body.style.left = '0'; document.body.style.right = '0'; document.body.style.width = '100%'; document.body.style.overflow = 'hidden'
    const focusable = () => [...drawer.querySelectorAll<HTMLElement>('button, input, [tabindex]:not([tabindex="-1"])')]
    focusable()[0]?.focus()
    const onKey = (event: globalThis.KeyboardEvent) => {
      if (event.key === 'Escape') onClose()
      if (event.key !== 'Tab') return
      const items = focusable(); if (!items.length) return
      const first = items[0]; const last = items[items.length - 1]
      if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus() }
      else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus() }
    }
    drawer.addEventListener('keydown', onKey)
    return () => { drawer.removeEventListener('keydown', onKey); document.body.classList.remove('customer-drawer-scroll-locked'); Object.assign(document.body.style, previous); window.scrollTo(0, scrollY) }
  }, [onClose])
  async function persist(value: number, confirmed: boolean) {
    setSaving(true); setError('')
    try { await saveWarehouseStockLpuUpdates(scopeKey, [{ productCode: row.productCode, lpu: value }], confirmed); setEditing(false); setConfirmValue(null); await onSaved() }
    catch (cause) { setError(cause instanceof Error ? cause.message : 'Litre / Birim güncellenemedi.') }
    finally { setSaving(false) }
  }
  function save() {
    const value = Number(draft.trim().replace(',', '.'))
    if (!Number.isFinite(value) || value <= 0) { setError('Pozitif bir Litre / Birim değeri girin.'); return }
    if (requiresLargeLpuConfirmation(row.lpu, value)) { setConfirmValue(value); return }
    void persist(value, false)
  }
  return <><button className="customer-drawer-backdrop-v7" type="button" aria-label="Ürün detayını kapat" onClick={onClose} /><aside ref={ref} className="customer-drawer-v7 warehouse-drawer-v1" role="dialog" aria-modal="true" aria-labelledby="warehouse-drawer-title-v1"><div className="drawer-topbar-v7"><div><span>DEPO STOKU</span><strong>Ürün detayı</strong></div><button type="button" aria-label="Ürün detayını kapat" onClick={onClose}>×</button></div><div className="drawer-body-v7"><section className="warehouse-drawer-hero-v1"><div className="warehouse-drawer-hero-head-v1"><div><span>Anlık Depo Stoku</span><h2 id="warehouse-drawer-title-v1">{productName(row)}</h2><code>{row.productCode}</code></div><em>● LIVE</em></div><div className="warehouse-drawer-metrics-v1"><article className="primary"><span>Toplam Litre</span><strong>{row.availableLitres === null ? '—' : formatNumber(row.availableLitres)}{row.availableLitres === null ? null : <small> Lt</small>}</strong></article><article><span>Stok</span><strong>{formatNumber(row.exactAvailableQuantity)}</strong></article></div></section><section className="drawer-section-v7 warehouse-drawer-info-v1"><header><span>ÜRÜN BİLGİLERİ</span><h3>Tanımlı ürün verisi</h3></header><div><article><span>Ürün Kodu</span><strong className="warehouse-drawer-code-v1">{row.productCode}</strong></article><article><span>Litre / Birim</span>{editing ? <div className="warehouse-inline-edit-v1"><input autoFocus inputMode="decimal" value={draft} onChange={(event) => setDraft(event.target.value)} aria-label="Litre / Birim" /><button type="button" className="save" disabled={saving} onClick={save}>{saving ? 'Kaydediliyor…' : 'Kaydet'}</button><button type="button" disabled={saving} onClick={() => { setEditing(false); setDraft(row.lpu === null ? '' : String(row.lpu)); setError('') }}>Vazgeç</button></div> : <div className="warehouse-lpu-read-v1"><strong>{row.lpu === null ? 'Tanımlı değil' : `${formatLpu(row.lpu)} Lt/Birim`}</strong>{admin ? <button type="button" onClick={() => setEditing(true)}>{row.lpu === null ? 'Tanımla' : 'Düzenle'}</button> : null}</div>}</article>{error ? <p className="warehouse-drawer-error-v1" role="alert">{error}</p> : null}</div></section><p className="warehouse-drawer-meta-v1"><span>Son başarılı yayın: {formatPublication(row.sourcePublishedAt)}</span><span>WAREHOUSE_STOCK v1 · FULL_REPLACE</span></p></div></aside>{confirmValue !== null ? <div className="warehouse-confirm-backdrop-v1"><section className="warehouse-confirm-v1" role="alertdialog" aria-modal="true" aria-labelledby="warehouse-confirm-title-v1"><h3 id="warehouse-confirm-title-v1">Büyük değişiklik</h3><p>{row.lpu === null ? '' : `${formatLpu(row.lpu)} → ${formatLpu(confirmValue)} değişikliği %25 veya daha fazla sapma oluşturuyor. `}Bu değişiklik Toplam Litre sonuçlarını önemli ölçüde etkileyebilir.</p><div><button type="button" onClick={() => setConfirmValue(null)}>Vazgeç</button><button type="button" className="primary" disabled={saving} onClick={() => void persist(confirmValue, true)}>Devam Et</button></div></section></div> : null}</>
}

function MissingLpuModal({ rows, drafts, setDrafts, saving, onClose, onSave }: { rows: WarehouseStockBusinessRow[]; drafts: Record<string, string>; setDrafts: Dispatch<SetStateAction<Record<string, string>>>; saving: boolean; onClose: () => void; onSave: () => void }) {
  const ref = useRef<HTMLElement>(null)
  useEffect(() => { const modal = ref.current; if (!modal) return; const onKey = (event: globalThis.KeyboardEvent) => { if (event.key === 'Escape' && !saving) onClose() }; modal.addEventListener('keydown', onKey); modal.querySelector<HTMLElement>('input, button')?.focus(); return () => modal.removeEventListener('keydown', onKey) }, [onClose, saving])
  return <div className="warehouse-modal-backdrop-v1"><section ref={ref} className="warehouse-modal-v1" role="dialog" aria-modal="true" aria-labelledby="warehouse-missing-title-v1"><header><div><span>LİTRE / BİRİM TANIMLAMA</span><h2 id="warehouse-missing-title-v1">Eksik ürünleri tamamla</h2><p>Yalnız bildiğiniz değerleri girin. Boş bıraktığınız ürünler eksik kalır; sistem 0 veya tahmini değer üretmez.</p></div><button type="button" aria-label="Pencereyi kapat" disabled={saving} onClick={onClose}>×</button></header><div className="warehouse-modal-table-wrap-v1"><table><thead><tr><th>Ürün Kodu</th><th>Ürün Adı</th><th>Litre / Birim</th></tr></thead><tbody>{rows.map((row) => <tr key={row.productCode}><td><code>{row.productCode}</code></td><td><strong>{productName(row)}</strong></td><td><input inputMode="decimal" value={drafts[row.productCode] ?? ''} onChange={(event) => setDrafts((current) => ({ ...current, [row.productCode]: event.target.value }))} placeholder="örn. 0,500" aria-label={`${productName(row)} Litre / Birim`} /></td></tr>)}</tbody></table></div><footer><small>Kısmi kayıt desteklenir. Boş bırakılan ürünler eksik listesinde kalır.</small><button type="button" disabled={saving} onClick={onSave}>{saving ? 'Kaydediliyor…' : 'Girilenleri Kaydet'}</button></footer></section></div>
}
