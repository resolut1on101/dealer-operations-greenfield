# Package 03 — Canonical Product Normalization Test Card

Package 03 is backend-only product normalization infrastructure. There is no standalone Package 03U Product Master screen.

## Fixed reference evidence

- `paket.xlsx` is **not uploadable** and is not a runtime publication source.
- Exact evidence SHA-256: `51fb373ca178b68a8ddd29a6ea8f65f54162137c78aaccfb9b7f93805ffffdf2`.
- Frozen reference: `paket-51fb373c-v1`.
- Evidence invariants: `331 observations / 84 product codes / 59 stable directed relations / 36 canonical products`.

## Runtime source roles

- Sellout = Geleneksel channel sales.
- KA İrsaliye = Modern/KA channel sales.
- Warehouse stock is a separate current-stock source in Package 03A.

## Acceptance invariants

1. `PRODUCT_CONVERSION` is retired/inactive and `paket.xlsx` cannot be recognized as a new Upload Center source.
2. Standard/Bira split codes normalize to one main canonical code. Example: `154525 -> 1/2 × 150021`, `154548 -> 1/4 × 150021`.
3. High-alcohol/Distile direction is reversed. Example: `152224 -> 24 × 152315` and canonical code is `152315`.
4. The 59 reference relations exactly conserve canonical quantity; no factor is inferred from product-name similarity.
5. A split-code sale fulfills FKNS for the same canonical product; one customer/point is counted once even if main and split codes both appear.
6. Sellout, KA, warehouse stock, stock days, target, forecast, safety stock and order need must consume canonical identity/quantity before product aggregation.
7. Backend quantities remain exact decimals/rationals. `10.75` stays `10.75` for all calculations. UX may display `11` only as presentation.
8. Unmapped product codes remain identity and are not dropped.
9. Technical mapping/reference tables remain admin/audit only; normal viewer has no Product Master/variant/LPU surface.
10. Runtime normalization readiness depends on active static reference + current Sellout + current KA; no runtime `paket.xlsx` publication is required.

## Result

- `Package 03 = backend canonicalization layer`
- `Package 03U = CANCELLED_NOT_REQUIRED`
- next user-facing product surfaces are operational modules (warehouse stock, Sellout, FKNS, planning).
