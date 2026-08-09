# Supabase Free-tier Baseline

**Doğrulama tarihi:** 2026-08-09
**Resmî kaynak:** <https://supabase.com/pricing>

| Kaynak | Free baseline |
|---|---:|
| PostgreSQL database | 500 MB / proje |
| Storage | 1 GB |
| Maximum individual file / global Storage upload | 50 MB |
| Egress | 5 GB |
| Cached egress | 5 GB |
| Active hosted projects | 2 |
| Otomatik backup | Dahil değil |
| Inactivity | Proje 1 hafta hareketsizlikten sonra pause olabilir |

Bu değerler business logic içine yazılmaz. Sadece planlama bütçesi, System Health threshold girdisi ve deployment-time doğrulama için kullanılır. Sağlayıcı limitleri değişebileceğinden **deployment sırasında yeniden doğrulanır**.

İki aktif hosted proje hakkı, ayrı **dev** ve **live** Supabase projeleri tarafından kullanılacaktır. `local`, Docker ile çalışır ve bu hosted proje kotasına dahil değildir. 50 MB upload limiti import iş kuralı değildir; Paket 01 tasarım/doğrulama ve deployment-time kontrol girdisidir.

Free planın otomatik backup sağlamaması nedeniyle ilk canlı yayın öncesinde (Paket 00C) mantıksal export/restore runbook ve rehearsal zorunludur.
