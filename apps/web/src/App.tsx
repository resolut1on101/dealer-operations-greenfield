import { useEffect, useState } from 'react'
import type { ApplicationRole } from '@dealer-operations/contracts'
import { UploadCenter } from './UploadCenter'
import { CustomerWorkspace } from './CustomerWorkspace'
import { applicationEnvironment, buildVersion, databaseMigrationVersion, isSupabaseConfigured, releasePackage, releaseState } from './lib/environment'
import { supabase } from './lib/supabase'
import { getVisibleNavGroups } from './lib/navigation'

const visiblePackageLabel = releasePackage

function releaseStateText() {
  if (releaseState === 'LIVE_TESTING') return 'Canlı'
  if (releaseState === 'VERIFIED') return 'Doğrulandı'
  return 'Engellendi'
}

export function App() {
  const [sidebarOpen, setSidebarOpen] = useState(true)
  const [mobileNavOpen, setMobileNavOpen] = useState(false)
  const [activeItem, setActiveItem] = useState('Müşteriler')
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
    if (error || !data) { setAuthMessage('Oturum doğrulandı ancak rol profili okunamadı. Sistem yöneticinize başvurun.'); return }
    setRole(data.role as ApplicationRole)
  }
  async function signIn(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); if (!supabase) return
    setLoadingAuth(true); setAuthMessage('')
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    if (error) setAuthMessage('Giriş yapılamadı. E-posta ve parolanızı kontrol edin.')
    else { setPassword(''); await loadProfile() }
    setLoadingAuth(false)
  }
  async function signOut() { if (!supabase) return; await supabase.auth.signOut(); setRole(null); setAuthMessage('Oturum kapatıldı.') }
  function chooseItem(item: string) { setActiveItem(item); setMobileNavOpen(false) }
  const authenticated = role !== null

  return <div className="app-shell">
    <header className="topbar"><button className="icon-button mobile-menu" type="button" aria-label="Menüyü aç" onClick={() => setMobileNavOpen(true)}>☰</button><div className="breadcrumbs"><span>Dealer Operations</span><span aria-hidden="true">/</span><strong>{activeItem}</strong></div><div className="utility-actions"><span className={`release-badge ${releaseState.toLowerCase()}`}>● {releaseStateText()}</span><span className="build-indicator">Package {visiblePackageLabel} · {buildVersion}</span>{authenticated ? <button className="text-button" type="button" onClick={signOut}>Çıkış yap</button> : null}</div></header>
    <aside className={`sidebar ${sidebarOpen ? 'open' : 'collapsed'} ${mobileNavOpen ? 'mobile-open' : ''}`} aria-label="Ana gezinme"><div className="brand-row"><span className="brand-mark" aria-hidden="true">DO</span><span className="brand-name">Dealer Operations</span><button className="icon-button collapse-button" type="button" aria-label="Yan menüyü daralt veya genişlet" onClick={() => setSidebarOpen((value) => !value)}>‹</button><button className="icon-button close-mobile" type="button" aria-label="Menüyü kapat" onClick={() => setMobileNavOpen(false)}>×</button></div><nav>{getVisibleNavGroups(role).map((group) => <section className="nav-group" key={group.label} aria-label={group.label}><h2>{group.label}</h2>{group.items.map((item) => <button className={activeItem === item ? 'nav-item active' : 'nav-item'} type="button" key={item} onClick={() => chooseItem(item)}><span className="nav-dot" aria-hidden="true" /><span>{item}</span></button>)}</section>)}</nav></aside>
    {mobileNavOpen ? <button className="scrim" type="button" aria-label="Menüyü kapat" onClick={() => setMobileNavOpen(false)} /> : null}
    <main className={`content ${sidebarOpen ? 'sidebar-open' : 'sidebar-collapsed'}`} aria-labelledby="page-title">
      {activeItem === 'Veri Yükleme' && authenticated ? <UploadCenter role={role} /> : activeItem === 'Müşteriler' && authenticated ? <CustomerWorkspace role={role} /> : <AccessSurface role={role} email={email} password={password} setEmail={setEmail} setPassword={setPassword} loading={loadingAuth} authMessage={authMessage} onSignIn={signIn} />}
    </main>
  </div>
}

function AccessSurface(props: { role: ApplicationRole | null; email: string; password: string; setEmail: (value: string) => void; setPassword: (value: string) => void; loading: boolean; authMessage: string; onSignIn: (event: React.FormEvent<HTMLFormElement>) => void }) {
  return <><section className="page-context"><p className="eyebrow">PACKAGE {visiblePackageLabel} · CANLI İŞLETİM TABANI</p><h1 id="page-title">Yönetim çalışma alanı</h1><p>Bu çalışma alanı authenticated session ve backend yayın durumlarına göre içerik sağlar. Browser state resmi business data değildir.</p></section><section className="status-grid" aria-label="Canlı sürüm durumu"><article className="status-panel"><p className="panel-label">Yayın durumu</p><strong>{releaseStateText()}</strong><span>Paket {visiblePackageLabel} · {applicationEnvironment}</span></article><article className="status-panel"><p className="panel-label">Resmî veri</p><strong>Published yüzeyler</strong><span>Yayınlanmamış import operasyonları viewer’a gösterilmez.</span></article><article className="status-panel"><p className="panel-label">Build kimliği</p><strong>{buildVersion}</strong><span>DB migration {databaseMigrationVersion}</span></article></section><section className="workbench" aria-labelledby="access-title"><div><p className="eyebrow">SİSTEM / TEST MERKEZİ</p><h2 id="access-title">Erişim durumu</h2><p>Viewer yalnız published business read surface görebilir. Teknik provenance/history ve mutation operasyonları admin-only’dir.</p></div>{props.role ? <div className="role-card"><span className="role-label">Oturum rolü</span><strong>{props.role === 'admin' ? 'Yönetici' : 'Görüntüleyici'}</strong><p>{props.role === 'admin' ? 'Upload Center mutation ve operational batch detail erişimi açık.' : 'Yalnız published read surface erişimi açık.'}</p></div> : isSupabaseConfigured ? <form className="login-form" onSubmit={props.onSignIn}><label>E-posta<input type="email" autoComplete="email" value={props.email} onChange={(event) => props.setEmail(event.target.value)} required /></label><label>Parola<input type="password" autoComplete="current-password" value={props.password} onChange={(event) => props.setPassword(event.target.value)} required /></label><button className="primary-button" type="submit" disabled={props.loading}>{props.loading ? 'Giriş yapılıyor…' : 'Giriş yap'}</button>{props.authMessage ? <p className="form-message" role="status">{props.authMessage}</p> : null}</form> : <div className="blocked-card" role="status"><strong>Kimlik yapılandırması eksik</strong><p>Bu build için Supabase genel anahtarları tanımlı değil.</p></div>}</section></>
}
