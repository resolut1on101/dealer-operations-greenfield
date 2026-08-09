# Supabase Free-tier Baseline

**Doğrulama tarihi:** 2026-08-09
**Resmî kaynak:** <https://supabase.com/pricing>

| Kaynak | Free baseline |
|---|---:|
| PostgreSQL database | 500 MB / proje |
| Storage | 1 GB |
| Egress | 5 GB |
| Cached egress | 5 GB |
| Otomatik backup | Dahil değil |
| Inactivity | Proje 1 hafta hareketsizlikten sonra pause olabilir |

Bu değerler business logic içine yazılmaz. Sadece planlama bütçesi, System Health threshold girdisi ve deployment-time doğrulama için kullanılır. Sağlayıcı limitleri değişebileceğinden **deployment sırasında yeniden doğrulanır**.

Free planın otomatik backup sağlamaması nedeniyle ilk canlı yayın öncesinde (Paket 00C) mantıksal export/restore runbook ve rehearsal zorunludur.
