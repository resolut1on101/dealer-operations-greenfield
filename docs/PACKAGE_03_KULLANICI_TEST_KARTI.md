# Package 03 — Kullanıcı Test Kartı

Status before user test: `LIVE_TESTING`

Package 03 is a backend/domain package; Product Master UX belongs to Package 03U. User acceptance therefore verifies the published product truth and that existing application behavior remains intact. Package 03 must not be marked `ACCEPTED` until the user explicitly says `PASS`.

## Test data / scope

Scope: `1237`

Published sources must be the exact current files:

- `PRODUCT_CONVERSION` → `paket.xlsx`
- `SELLOUT` → `Sellout Raporu (5).xlsx`
- `KA_DELIVERY` → `İrsaliye Listesi (2).xlsx`

## User-visible acceptance points

1. Upload Center still opens and normal Package 01 upload/publication behavior is not broken.
2. The three Package 03 source kinds can be recognized/published under scope `1237` without the duplicate `Miktar` columns in `paket.xlsx` overwriting each other.
3. Technical LIVE proof reports exactly:
   - 136 product variants
   - 331 conversion observations
   - 84 conversion products
   - 59 directed conversion relations
   - 36 conversion components
   - 25 business product families
4. Product-name states are exactly `111 RESOLVED / 25 PARTIAL / 0 BLOCKED`.
5. Family states are exactly `114 RESOLVED / 22 PARTIAL / 0 BLOCKED`.
6. Active-LPU states are exactly `109 RESOLVED / 27 PARTIAL / 0 BLOCKED`.
7. Active-LPU source counts are exactly `71 Sellout / 18 KA / 20 conversion graph`.
8. The 22 products that have only negative Sellout return rows remain `PARTIAL / NULL`; they must not be turned into positive LPU evidence. `225887` is a spot-check example.
9. The five conversion products without an absolute anchor remain `PARTIAL / NULL`: `150783`, `151942`, `151943`, `152225`, `152316`.
10. Product `151428` keeps Sellout as the active source while the small KA source variance remains visible; the system must not silently replace the Sellout coefficient or invent a tolerance.
11. Quantity-UOM resolution is exactly `84 RESOLVED / 52 PARTIAL / 0 BLOCKED`; the 84 graph products have one stable UOM.
12. Viewer users cannot directly read Package 03 base/provenance tables; the bounded business/summary RPCs remain readable.
13. Existing Package 02U Customers/Organization remains functional after deploy.

## PASS rule

If the LIVE technical report proves the exact invariants above and the application has no regression, user may reply:

`PASS`

Result:
- `Package 03 = ACCEPTED` (Approved on 2026-08-14)
- `Technical release = PASS`
- `Production UAT = PASS`
- `Package 03U = UNBLOCKED`

