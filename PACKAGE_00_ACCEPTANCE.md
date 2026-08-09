# Paket 00 Kapanış Kanıtı

**Durum:** `REVIEW_REQUIRED`
**Kullanıcı teknik onayı:** `BEKLİYOR`

## Hedef repo ve referans koruması

- **Hedef repo:** `C:\Users\monds\Desktop\YENI\dealer-operations-greenfield`
- **REFERANS_REACT:** `C:\Users\monds\Desktop\YENI\REFERANS`
- **REFERANS_KESAN:** `C:\Users\monds\Desktop\YENI\REFERANS 2\KESAN`

Hedef repo iki READ-ONLY referans yolunun dışındadır. Her iki referans yolunda `.git` yoktur; bu yüzden `git status`/`git diff` uygulanamaz. Önceki salt-okunur envanter kanıtı: REFERANS_REACT 2.892 dosya, son yazım `2026-08-06 01:39:47 +03:00`; REFERANS_KESAN 21 dosya, son yazım `2026-08-05 21:29:35 +03:00`. Paket 00 boyunca referanslarda write, dependency install, build veya uygulama kodu üretimi yapılmadı.

## Stack, import yönü ve ortamlar

Seçilen stack ve alternatif değerlendirmesi [TECH_STACK_DECISION.md](TECH_STACK_DECISION.md) içindedir. Supabase/PostgreSQL kullanıcı hedefidir; React/Vite referanstan otomatik miras alınmamıştır. Paket 01 canonical import yönü Browser Web Worker parse → chunk/bulk staging → PostgreSQL RPC/set-based validation/reconciliation → candidate publication → atomic publish şeklindedir. Uzun XLSX parse ve satır-başı iş Edge Function’a taşınmaz.

`local` ve `dev` yalnız synthetic/test data; `live` yalnız published business data içindir. Paket 00’da gerçek müşteri, sellout veya finans verisi seed edilmedi. `local` Docker instance’tır; ayrı `dev` ve `live` hosted Supabase proje/secret’leri gerekir. İlk live deploy Paket 00C’dedir.

**DEV doğrulaması:** explicit project ref `enlcfbbkfqijspxhngzo` linklendi. `db push --linked` ile üç Package 00 migration uygulandı; remote schema sorgusu 3 migration, `admin,viewer`, `authenticated_read,admin_write` ve iki bootstrap fonksiyonu döndürdü. `db query --linked --file supabase/tests/rls-foundation.sql` synthetic test kullanıcılarıyla çalıştı ve transaction sonunda rollback yaptı. LIVE’a bağlantı veya deploy yapılmadı.

## Rol, RLS ve admin bootstrap

- Contract/migration yalnız `admin` ve `viewer` rollerini tanımlar; capability, scope veya permission matrisi yoktur.
- `user_profiles` business/read modeli değildir. Özel “yalnız kendi profilini okuma” istisnası yoktur: authenticated `authenticated_read` ile okuyabilir, yalnız admin `admin_write` ile mutation yapabilir. Business read tarafına müşteri/temsilci bazlı restriction eklenmemiştir.
- `auth.users` insert trigger’ı aynı UUID ile deterministik `user_profiles` kaydı ve varsayılan `viewer` rolü üretir.
- `bootstrap_first_admin(exact_user_uuid)` yalnız trusted `service_role` çağrısına açıktır; browser’da service role bulunmaz. Hedef profil yoksa hata verir, aynı admin için idempotenttir, başka admin varsa hata verir. Runbook: [environment-and-release.md](docs/runbooks/environment-and-release.md).
- Sürüm kontrollü [rls-foundation.sql](supabase/tests/rls-foundation.sql) anon read/write redlerini; viewer read/mutation/escalation reddini; trusted bootstrap’ı; admin read/write’ı ve admin/viewer dışı enum değerinin reddini doğrular. CI migration-check job’ında da çalışır.

## Source of truth ve secret/config

- Runtime kodunda `localStorage`, `indexedDB`, `sessionStorage` kullanımı yoktur; sadece iki mimari/kabul belgesinde yasak ilke olarak geçer.
- Resmî business data kaynağı yalnız Supabase PostgreSQL’dir.
- `.env`, `.env.local`, `.env.production` yoktur; yalnız değer içermeyen `.env.example` vardır. `.gitignore`: `.env`, `.env.*`, `!.env.example`.
- service-role/API/private/Gemini benzeri gerçek secret veya hardcoded Supabase secret bulunmadı. Production hedefi local/dev config’den türetilmez.

## Free-tier kontrolü

[FREE_TIER_BASELINE.md](FREE_TIER_BASELINE.md), 2026-08-09 tarihinde resmi [Supabase pricing](https://supabase.com/pricing) kaynağından doğrulandı: proje başına 500 MB DB, 1 GB Storage, 5 GB egress, 5 GB cached egress, 50 MB maksimum dosya upload, 2 active hosted project, otomatik backup yok ve bir hafta inactivity sonrası pause. İki hosted proje hakkı dev+live içindir; limitler business logic’e hardcode edilmez ve deployment sırasında yeniden doğrulanır.

## Son yerel doğrulama

| Komut | Exit | Sonuç |
|---|---:|---|
| `npm ci` | 0 | PASS — 238 paket, 0 vulnerability |
| `npm run lint` | 0 | PASS |
| `npm run typecheck` | 0 | PASS |
| `npm test` | 0 | PASS — 2 test |
| `npm run build` | 0 | PASS |
| `npm run verify` | 0 | PASS |
| `npm run supabase -- db reset --local` | 0 | PASS — 3 migration uygulandı |
| `npm run test:rls` | 0 | PASS — transaction rollback ile RLS/bootstrap entegrasyon testi |
| `npm run supabase -- db query --linked --file supabase/tests/rls-foundation.sql` | 0 | PASS — DEV üzerinde synthetic/rollback RLS testi |

## First-admin concurrency

**Current verification note (2026-08-09):** the new fourth migration is locally reset and tested. The previously linked DEV project has the first three Package 00 migrations; applying and rechecking the fourth migration requires a renewed trusted Supabase CLI access token. No previous token is stored in this repository, and no LIVE target is touched. User technical stack approval is also still pending.

- Migration `20260809000003_first_admin_global_lock.sql` makes `bootstrap_first_admin(exact_user_uuid)` acquire a deterministic transaction-scoped PostgreSQL advisory lock before it inspects or mutates `user_profiles`.
- The version-controlled `scripts/test-first-admin-concurrency.mjs` test is invoked by `npm run test:rls` and therefore by CI's `migration-check` job after a local reset. It opens two independent database sessions for two different UUID targets. The first session wins; the second waits for the global lock, observes the newly-created admin, and fails. The test asserts the final roles are exactly one `admin` and one `viewer`.
- Local result after the four Package 00 migrations: `PASS` -- `Concurrent first-admin bootstrap PASS: two independent DB sessions produced one admin and one rejected call.`

## Git ve CI

- Concurrency foundation verification commit: `487596efdffb458ae6485e28db2086e05286cc9e`.
- GitHub Actions [CI run #4](https://github.com/resolut1on101/dealer-operations-greenfield/actions/runs/31306505864) for that commit: `quality = success`, `migration-check = success` (including the clean reset and two-session concurrency test).
- The safe review archive is regenerated only with `npm run review:zip` from a clean `HEAD`; its filename embeds the exact archived `HEAD` SHA. It is a git-archive output, not a working-directory ZIP, and is ignored by Git.

- Foundation commit: `7465796302ce66db01f873c6392369f12327c7f5`
- Önceki kabul kaydı commit: `a5d4e3c127cca58b87407f144877b3ca6806b9a4`
- Bu güncellemenin kapanış SHA’sı commit oluşturulduktan sonra dış kapanış mesajında verilir; belge kendi commit hash’ini içeremez.
- Remote: `origin https://github.com/resolut1on101/dealer-operations-greenfield.git`; `main` push edildi.
- GitHub Actions [CI run #1](https://github.com/resolut1on101/dealer-operations-greenfield/actions/runs/31305308577): `quality = success`, `migration-check = success`. **CI: PASS.**

## Review bundle güvenliği

- `npm run review:zip`, yalnız temiz ve commit edilmiş tracked dosyalardan `git archive HEAD` ile ZIP üretir; çalışma klasörü doğrudan arşivlenmez.
- ZIP üretilmeden önce tracked path kontrolü `.git/`, `node_modules/`, `dist/`, `coverage/`, `playwright-report/`, `test-results/`, `.env`, `.env.*` (boş şablon `.env.example` hariç), `supabase/.temp/`, cache/temp ve log yollarını reddeder.
- Aynı ön kontrol private key, JWT-benzeri değer ve non-empty service-role/API/private/Gemini/OpenAI secret atamalarını tarar; bulgu varsa ZIP oluşturmaz. Review bundle içinden commit SHA bu belgeden görülebilir, `.git` eklenmez.
- Review Bundle: `PASS` (bu mekanizma çalıştırılıp içeriği doğrulanır); Secret Scan: `PASS`; Excluded Runtime: `PASS`.

## Dış veri referansı

Paket 01’in ileride kullanacağı repo-dışı READ-ONLY veri referans yapısı `C:\Users\monds\Desktop\YENI\VERI_REFERANS` olarak kaydedildi. Klasör sözleşmesi ve gerçek Excel koruma kuralları [data-reference-boundary.md](docs/architecture/data-reference-boundary.md) içindedir. Bu kayıt import motoru, parser, database import tablosu veya fixture üretimi içermez.

## Açık bloklayıcılar

1. Kullanıcının teknik stack onayı.
