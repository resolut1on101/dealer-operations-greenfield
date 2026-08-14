# Package 03A Acceptance Record

**Package:** Package 03A — WAREHOUSE_STOCK / Malzemeler / Anlık Depo Stoku  
**Status:** `PACKAGE03A_WAREHOUSE_STOCK_ACCEPTED` / `CLOSED`  
**Acceptance Date:** 2026-08-14  
**Acceptance Basis:** Explicit LIVE user acceptance received for both Admin and Viewer roles.

---

## Technical & Release Evidence

- **Source Contract:** `WAREHOUSE_STOCK v1` (`FULL_REPLACE`, Sheet: `SAPUI5 dışa aktarımı`, exact 3 columns: `Malzeme numarası`, `Malzeme tanımı`, `Tahditsiz kullanılabilir`).
- **Real Source Evidence:** Workbook SHA-256 `1cee1b283cbadf7839d14c30cb0ef5cd872438b236f94139d1ad13c9dd8efc9a` (84 raw rows, 84 unique codes, 0 duplicates, 0 missing required fields, 0 non-positive quantities).
- **Canonical Product Normalization:** 84 raw rows normalize through accepted Package 03 reference `paket-51fb373c-v1` into 63 canonical business rows (53 mapped, 31 identity preserved, 21 split/case rows collapsed; standard `150021 = 1216.25`, high-alcohol `152327 = 197`, missing LPU remains `NULL / PARTIAL`).
- **Database Migration:** `20260814000018_package_03a_warehouse_stock.sql` applied to LIVE target `ncwtlaiormtunpryxjmu`.
- **DEV Isolation:** DEV project `enlcfbbkfqijspxhngzo` remained untouched.
- **Production Web Deployment:** Deployment ID `cc02275d-be19-4ef4-a272-57c59a648799` on `https://dealer-operations-greenfield.pages.dev` (build `d5e6a26`).
- **Final Source Snapshot:** `dealer-operations-greenfield-package-03a-final-d5e6a26.zip` (SHA-256: `484a5b2e7a1416cccaba5e7c8b5c833742f1c0fef17b130adf49e17903b82408`).

---

## LIVE User Acceptance

- **Admin Acceptance:** `PASS` (Observed on LIVE: role admin, Upload Center loads and recognizes WAREHOUSE_STOCK v1, reaches READY, publication visible with 84 records and PUBLISHED status at 14.08.2026 14:57).
- **Viewer Acceptance:** `PASS` (Observed on LIVE: role viewer, read-only publication summary and provenance available, mutation/admin controls correctly absent, RLS isolation verified).

---

## Decision

Package 03A is formally marked **`PACKAGE03A_WAREHOUSE_STOCK_ACCEPTED`** and **`CLOSED`**.  
The next planned package is **`03AU — D4 Anlık Stok Görünümü UX/UI`**.
