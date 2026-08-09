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

## Git ve CI

- Foundation commit: `7465796302ce66db01f873c6392369f12327c7f5`
- Önceki kabul kaydı commit: `a5d4e3c127cca58b87407f144877b3ca6806b9a4`
- Bu güncellemenin kapanış SHA’sı commit oluşturulduktan sonra dış kapanış mesajında verilir; belge kendi commit hash’ini içeremez.
- Git remote yoktur: `REMOTE: USER DECISION REQUIRED`.
- `.github/workflows/ci.yml` quality ve migration-check (reset + `test:rls`) tanımlar; remote/push olmadığından GitHub Actions çalıştırılmadı. **CI: FAIL (CONFIGURED_BUT_NOT_RUN; gerçek CI PASS değildir).**

## Açık bloklayıcılar

1. Kullanıcının teknik stack onayı.
2. Kullanıcının seçtiği Git remote, `main` push ve gerçek GitHub Actions quality/migration-check PASS kanıtı.
3. Kullanıcının sağlayacağı ayrı Supabase `dev` proje ref/bağlantısı: explicit target link, migration listesi ve RLS foundation doğrulaması. Live’a deploy edilmeyecektir.
