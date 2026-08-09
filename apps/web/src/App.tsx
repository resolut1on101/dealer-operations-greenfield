import { useEffect, useState } from 'react'
import type { ApplicationRole } from '@dealer-operations/contracts'
import {
  applicationEnvironment,
  buildVersion,
  databaseMigrationVersion,
  isSupabaseConfigured,
  releasePackage,
  releaseState,
} from './lib/environment'
import { supabase } from './lib/supabase'

type NavGroup = { label: string; items: string[] }

const navGroups: NavGroup[] = [
  { label: 'GENEL', items: ['Genel Bakış'] },
  { label: 'SATIŞ & MÜŞTERİ', items: ['Müşteriler', 'Sellout', 'FKNS'] },
  { label: 'STOK & PLANLAMA', items: ['Depo Stoku', 'Ticari Stok', 'Talep & Sipariş Planlama'] },
  { label: 'OPERASYON', items: ['Siparişler', 'Sevkiyat', 'Fatura Kontrol'] },
  { label: 'FİNANS', items: ['Cari 360', 'Tahsilatlar', 'Çek / Senet', 'Finansal Analiz'] },
  { label: 'ANALİZ', items: ['Rapor Merkezi', 'AI Asistan'] },
  { label: 'YÖNETİM', items: ['Veri Yükleme', 'Sistem Sağlığı', 'Ayarlar'] },
]

function releaseStateText() {
  if (releaseState === 'LIVE_TESTING') return 'Canlı testte'
  if (releaseState === 'VERIFIED') return 'Doğrulandı'
  return 'Engellendi'
}

export function App() {
  const [sidebarOpen, setSidebarOpen] = useState(true)
  const [mobileNavOpen, setMobileNavOpen] = useState(false)
  const [activeItem, setActiveItem] = useState('Genel Bakış')
  const [role, setRole] = useState<ApplicationRole | null>(null)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [authMessage, setAuthMessage] = useState('')
  const [loadingAuth, setLoadingAuth] = useState(false)

  useEffect(() => { void loadProfile() }, [])

  async function loadProfile() {
    if (!supabase) return
    const { data: { session } } = await supabase.auth.getSession()
    if (!session) return
    const { data, error } = await supabase.from('user_profiles').select('role').eq('user_id', session.user.id).single()
    if (error || !data) {
      setAuthMessage('Oturum doğrulandı ancak rol profili okunamadı. Sistem yöneticinize başvurun.')
      return
    }
    setRole(data.role as ApplicationRole)
  }

  async function signIn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!supabase) return
    setLoadingAuth(true)
    setAuthMessage('')
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) setAuthMessage('Giriş yapılamadı. E-posta ve parolanızı kontrol edin.')
    else {
      setPassword('')
      await loadProfile()
    }
    setLoadingAuth(false)
  }

  async function signOut() {
    if (!supabase) return
    await supabase.auth.signOut()
    setRole(null)
    setAuthMessage('Oturum kapatıldı.')
  }

  function chooseItem(item: string) {
    setActiveItem(item)
    setMobileNavOpen(false)
  }

  return (
    <div className="app-shell">
      <header className="topbar">
        <button className="icon-button mobile-menu" type="button" aria-label="Menüyü aç" onClick={() => setMobileNavOpen(true)}>☰</button>
        <div className="breadcrumbs"><span>Dealer Operations</span><span aria-hidden="true">/</span><strong>{activeItem}</strong></div>
        <div className="utility-actions">
          <span className={`release-badge ${releaseState.toLowerCase()}`}>{releaseStateText()}</span>
          <span className="build-indicator" title={`Paket ${releasePackage}`}>build {buildVersion}</span>
          {role ? <button className="text-button" type="button" onClick={signOut}>Çıkış yap</button> : null}
        </div>
      </header>

      <aside className={`sidebar ${sidebarOpen ? 'open' : 'collapsed'} ${mobileNavOpen ? 'mobile-open' : ''}`} aria-label="Ana gezinme">
        <div className="brand-row">
          <span className="brand-mark" aria-hidden="true">DO</span><span className="brand-name">Dealer Operations</span>
          <button className="icon-button collapse-button" type="button" aria-label="Yan menüyü daralt veya genişlet" onClick={() => setSidebarOpen((value) => !value)}>‹</button>
          <button className="icon-button close-mobile" type="button" aria-label="Menüyü kapat" onClick={() => setMobileNavOpen(false)}>×</button>
        </div>
        <nav>
          {navGroups.map((group) => (
            <section className="nav-group" key={group.label} aria-label={group.label}>
              <h2>{group.label}</h2>
              {group.items.map((item) => (
                <button className={activeItem === item ? 'nav-item active' : 'nav-item'} type="button" key={item} onClick={() => chooseItem(item)}>
                  <span className="nav-dot" aria-hidden="true" /><span>{item}</span>
                </button>
              ))}
            </section>
          ))}
        </nav>
      </aside>
      {mobileNavOpen ? <button className="scrim" type="button" aria-label="Menüyü kapat" onClick={() => setMobileNavOpen(false)} /> : null}

      <main className={`content ${sidebarOpen ? 'sidebar-open' : 'sidebar-collapsed'}`} aria-labelledby="page-title">
        <section className="page-context">
          <p className="eyebrow">PAKET 00C · CANLI İŞLETİM TABANI</p><h1 id="page-title">{activeItem}</h1>
          <p>Ürün alan verileri henüz yayınlanmadı. Bu canlı kabuk, doğrulanmış erişim ve güvenli sürüm görünürlüğü için hazırdır.</p>
        </section>
        <section className="status-grid" aria-label="Canlı sürüm durumu">
          <article className="status-panel"><p className="panel-label">Yayın durumu</p><strong>{releaseStateText()}</strong><span>Paket {releasePackage} · {applicationEnvironment}</span></article>
          <article className="status-panel"><p className="panel-label">Resmî veri</p><strong>Henüz yayın yok</strong><span>Alan verisi veya deneme veri kümesi gösterilmez.</span></article>
          <article className="status-panel"><p className="panel-label">Build kimliği</p><strong>{buildVersion}</strong><span>DB migration {databaseMigrationVersion}</span></article>
        </section>
        <section className="workbench" aria-labelledby="access-title">
          <div><p className="eyebrow">SİSTEM / TEST MERKEZİ</p><h2 id="access-title">Erişim durumu</h2><p>Görüntüleme yüzeyleri kimliği doğrulanmış kullanıcılar içindir. Yayınlama ve veri değişikliği, ilgili alan paketleri gelene kadar bu kabukta sunulmaz.</p></div>
          {role ? (
            <div className="role-card"><span className="role-label">Oturum rolü</span><strong>{role === 'admin' ? 'Yönetici' : 'Görüntüleyici'}</strong><p>{role === 'admin' ? 'Yönetici hesabı hazır; alan mutasyonları sonraki paketlerde açılacaktır.' : 'Görüntüleyici hesabı yalnızca okuma kabuğuna erişir; yayınlama yüzeyi yoktur.'}</p></div>
          ) : isSupabaseConfigured ? (
            <form className="login-form" onSubmit={signIn}>
              <label>E-posta<input type="email" autoComplete="email" value={email} onChange={(event) => setEmail(event.target.value)} required /></label>
              <label>Parola<input type="password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} required /></label>
              <button className="primary-button" type="submit" disabled={loadingAuth}>{loadingAuth ? 'Giriş yapılıyor…' : 'Giriş yap'}</button>
              {authMessage ? <p className="form-message" role="status">{authMessage}</p> : null}
            </form>
          ) : <div className="blocked-card" role="status"><strong>Kimlik yapılandırması eksik</strong><p>Bu yerel build için Supabase genel anahtarları tanımlı değil. Canlı buildde giriş için gerekli genel yapılandırma yayınlanır.</p></div>}
        </section>
      </main>
    </div>
  )
}
