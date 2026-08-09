# Paket 00 — Teknik Yığın Kararı

**Karar tarihi:** 2026-08-09
**Kapsam:** Greenfield teknik temel; business domain, import motoru ve D0 tasarımı içermez.

## Seçilen yaklaşım

- **Frontend:** React 19, TypeScript, Vite, React Router, TanStack Query ve Zod.
- **Backend/API:** Ayrı bir sürekli çalışan Node API yoktur. Normal read yüzeyleri Supabase’in RLS korumalı API’sine; güvenilir mutation, publish ve daha sonraki ağır süreçler version-controlled Supabase Edge Functions veya PostgreSQL RPC’lerine gider.
- **Veri katmanı:** Supabase PostgreSQL resmî ve tek source of truth’tur. Auth ve Storage Supabase üzerinden sağlanır.
- **Dağıtım:** Statik frontend Cloudflare Pages; backend/data ayrı Supabase `dev` ve `live` projeleridir. Paket 00 canlı deploy içermez; ilk canlı yayın Paket 00C’dedir.

**Supabase/PostgreSQL hedefi kullanıcı kararıdır.** Bu kayıt, onay verilen hedefe göre teknik seçimi belgeler; otomatik teknoloji mirası değildir.

## Neden bu seçim

React/Vite, eski React/Vite referansından devralınmış değildir. Bağımsız değerlendirme sonucunda seçilmiştir: SSR gereksinimi olmayan, tablo/ağır okunabilir veri yüzeyleri olan bir SPA için hızlı derleme, yalın çalışma zamanı ve güçlü TypeScript ekosistemi sağlar. Supabase PostgreSQL ise RLS, migration, Auth, Storage ve yayınlanmış verinin cihazlar arası tutarlılığı için tek yönetilen tabanda çözüm sunar.

Tarayıcı sadece publishable key kullanır. `service_role` ve diğer gizli anahtarlar tarayıcıya girmez. Browser cache resmî veri değildir; published data ve metrikler PostgreSQL’den gelir.

## Anlamlı alternatifler

| Alternatif | Avantaj | Dezavantaj / neden seçilmedi |
|---|---|---|
| Next.js + SSR + route handlers | SSR, tek framework içinde server route imkânı | Bu aşamada SSR ihtiyacı yok; server runtime, deploy ve secret yönetimi karmaşıklığını artırır. |
| React SPA + ayrı Node/NestJS API + yönetilen PostgreSQL | Tam backend kontrolü, kurum içi standartlara uyum | Auth, RLS eşdeğeri, Storage, migration ve hosting için ek bileşen/operasyon gerekir; free-tier maliyet ve bakım yüzeyi büyür. |
| Cloudflare Workers + D1 | Edge yakınlığı ve basit küçük API’ler | PostgreSQL uyumluluğu, transactional finansal/integrity gereksinimleri ve gelecekteki bulk data işleri için uygun ana kaynak değildir. |
| Supabase + React/Vite (seçilen) | PostgreSQL, RLS, Auth, Storage, local CLI ve düşük operasyon | Sağlayıcı limitleri izlenmeli; free plan inactivity/pause ve backup sınırlamaları runbook ile yönetilmelidir. |

## Geliştirme karmaşıklığı ve yüksek hacimli import etkisi

Paket 00 import motoru kodlamaz. **10K/25K/50K XLSX parse işlemi varsayılan olarak Supabase Edge Function içinde yapılmayacaktır.** Paket 01’in canonical yönü şudur: **Browser Web Worker parse → chunk/bulk staging → PostgreSQL RPC/set-based validation/reconciliation → candidate publication → atomic publish.** Edge Functions yalnız gerektiğinde güvenilir server-side orchestration/security boundary olarak kullanılabilir; uzun XLSX parsing ve satır-başı işlem Edge Function’a taşınamaz. Satır başına HTTP çağrısı, satır başına transaction veya tarayıcıda on binlerce DOM satırı yasaktır. Bu stack Web Worker, Storage evidence, SQL bulk/RPC, keyset pagination ve aggregate read model yaklaşımını destekler.

## Free-tier ve deploy etkisi

Frontend’in statik hosting’e ayrılması uygulama sunucusu maliyetini azaltır. Supabase Free kapasitesi veri kopyalarının azaltılmasını, raw Excel’in Storage’da tutulmasını ve database/storage/egress kullanımının izlenmesini gerektirir. Free limitleri iş mantığına hardcode edilmez; yalnız planlama, System Health eşikleri ve deployment-time kontrol girdisidir.

Detaylı güncel baseline: [FREE_TIER_BASELINE.md](FREE_TIER_BASELINE.md).

## Kullanıcı teknik onayı

**KULLANICI TEKNİK ONAYI: BEKLİYOR**

Bu karar, kullanıcı açıkça onaylamadan `APPROVED` durumuna geçirilmez.
