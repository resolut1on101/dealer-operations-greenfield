# Package 03 — Real Data Evidence (Final Plan-Aligned)

Scope: `1237`

This evidence was derived from the three read-only real workbooks supplied for Package 03. The workbooks are not committed into application source. Package 01 remains the raw source/provenance store; Package 03 stores compact product resolution, exact conversion relations, candidate coefficients, and current/history read models only.

## Binding calculation corrections

Package 03 follows the binding stock/product contract:

- Sellout LPU uses **valid positive rows only** for the same product code.
- The Sellout candidate is `Σ Litre / Σ Miktar`; row-ratio equality is not a business rule.
- KA uses the same aggregate-ratio form when it is the selected evidence source.
- Negative Sellout rows are return/event evidence, not positive LPU evidence. A product with only negative return rows therefore remains `PARTIAL / NULL` unless KA or a verified conversion graph supplies an absolute LPU.
- Evidence priority remains `Sellout -> KA -> verified conversion graph -> approved manual`.
- Lower-priority disagreement does not silently replace the active higher-priority LPU. Candidate values and source variance remain visible.
- Conversion factors and graph consistency are checked as rational quantity relationships. Canonical LPU evidence keeps numerator/denominator values so the implementation does not depend on an arbitrary 9-decimal rounding gate.

## Source identity

| Source | File | Rows | SHA-256 |
|---|---|---:|---|
| PRODUCT_CONVERSION | `paket.xlsx` | 331 | `51fb373ca178b68a8ddd29a6ea8f65f54162137c78aaccfb9b7f93805ffffdf2` |
| SELLOUT | `Sellout Raporu (5).xlsx` | 12,666 | `cd937d02c0fdf6eda155593ab5d4e5ca43ccce60cb0352a6706e43544fac6c68` |
| KA_DELIVERY | `İrsaliye Listesi (2).xlsx` | 1,587 | `eefa6f383482ceec1931a61474d91d8f2bcc7c1216daaa909a38058b25ca3cab` |

All rows in the three supplied workbooks carry embedded distributor/plant scope `1237` (`Üretim yeri`, `Bayi/Distribütör`, `Bayi/Dist Kodu`). Materialization rejects workbook-carried scope that differs from the declared Package 01 publication scope.

Materialization is also bound to the explicit Package 03 source-contract versions (`PRODUCT_CONVERSION v1`, `SELLOUT v1`, `KA_DELIVERY v1`). A later header/parser contract cannot silently change Product Domain semantics; it requires an explicit adapter/version update.

## Conversion evidence

`paket.xlsx` verifies:

- 331 conversion observations
- 84 distinct product codes
- 59 stable directed conversion relations
- 48 undirected relation pairs
- 36 connected conversion components
- 84 nodes / 48 undirected edges / 36 components, therefore the supplied graph is a forest
- 0 repeated directed relations with conflicting exact quantity ratios
- 0 non-positive/invalid conversion quantities
- 84 / 84 conversion products have one stable quantity UOM in the supplied graph
- quantity-UOM distribution: `KL=46`, `TVA=19`, `ADT=16`, `KAS=3`

A product code carrying multiple quantity UOMs inside the conversion graph is now a real blocking invariant because the same factor would otherwise have ambiguous physical meaning.

The known rejected historical mapping `154558/154559 -> 150003` is absent and is explicitly refused by the materializer. The supplied source instead contains the valid relations `151830 -> 154558` and `151830 -> 154559`.

## LPU evidence

Current real-source union: **136 product variants**.

Positive direct evidence:

- products with positive Sellout LPU candidate: **71**
- products with positive KA LPU candidate: **41**
- products with positive candidates in both Sellout and KA: **23**
- exact Sellout/KA aggregate agreement: **22**
- non-zero Sellout/KA source variance: **1** (`151428`)
- graph products with an absolute graph candidate: **79 / 84**

Expected canonical active-LPU state:

- `RESOLVED`: **109**
- `PARTIAL`: **27**
- `BLOCKED`: **0**
- active from Sellout: **71**
- active from KA: **18**
- active from verified conversion graph: **20**

Verification-state distribution:

- `cross_source_verified`: **22**
- `sellout_verified`: **49**
- `ka_verified`: **18**
- `derived_pending`: **20**
- `missing`: **27**
- `unit_inconsistent`: **0** in the current real data

The 27 `PARTIAL / NULL` LPU products split into two evidence classes:

### A. Five conversion products with no absolute anchor

- `150783`
- `151942`
- `151943`
- `152225`
- `152316`

Their relative conversion ratios are known, but no positive Sellout/KA anchor exists in the supplied evidence. Absolute LPU is therefore not invented.

### B. Twenty-two Sellout products observed only as negative returns in this source period

- `225030`
- `225038`
- `225295`
- `225791`
- `225826`
- `225836`
- `225887`
- `225899`
- `226214`
- `226216`
- `226256`
- `226257`
- `226546`
- `226550`
- `226648`
- `226685`
- `226733`
- `226747`
- `226773`
- `226816`
- `226825`
- `226931`

These rows remain valid Sellout return events and may still provide product-name/family evidence, but negative `Miktar`/`Litre` pairs are not valid positive LPU candidates. In particular, `225887` is now correctly `PARTIAL / NULL`, not falsely `BLOCKED` by comparing two negative return ratios.

### Source variance example — `151428`

- Sellout positive aggregate: `2133.000 / 375.000 = 5.688`
- KA positive aggregate: `278.760 / 49 = 5.688979591836734693877...`
- active source remains Sellout by approved priority
- absolute source variance is preserved as `0.000979591836734693877...`
- relative source variance is preserved as `0.0001722207870489968...`

No unapproved tolerance is invented. The higher-priority active value and lower-priority disagreement are both retained.

## Product family and product-name evidence

Product family is never inferred from product-name similarity.

Across the 136-variant union:

- distinct evidenced business families: **25**
- family `RESOLVED / PARTIAL / BLOCKED`: **114 / 22 / 0**
- product name `RESOLVED / PARTIAL / BLOCKED`: **111 / 25 / 0**

Within the 84 conversion-product universe:

- family `RESOLVED / PARTIAL / BLOCKED`: **79 / 5 / 0**
- LPU `RESOLVED / PARTIAL / BLOCKED`: **79 / 5 / 0**

34 of 36 conversion components contain exactly one stable Sellout family seed and may propagate that already-evidenced business family. The two unanchored components contain the same five partial conversion codes listed above.

Business family and conversion component remain separate concepts. The same business family label can legitimately occur in multiple disconnected conversion components; a graph component is not itself treated as a product family.

## Variant metadata contract

The current source set can safely resolve:

- `quantity_uom` for all 84 conversion products from `paket.xlsx`
- active LPU / candidate sources as described above
- `volume_tracked=true` only where active LPU is resolved; unresolved volume-tracking remains unknown rather than false

The supplied Package 03 sources do **not** provide approved values for:

- `units_per_case`
- `unit_volume_ml`
- `canonical_stock_variant_code`
- `replenishment_variant_code`

These are retained as first-class nullable source-pending downstream attributes and are not guessed from product names. Stock/case/order calculations that require them remain dependent on their approved later source/policy.

## Storage / history rule

Package 03 does not copy the 12,666 Sellout rows or 1,587 KA rows into new domain observation tables. Raw rows remain in Package 01 evidence. Package 03 persists compact per-run variant resolutions and aggregated conversion edges. Variant resolution rows carry explicit system-valid `valid_from` / `valid_to` periods so future publications preserve prior canonical product truth without duplicating raw-domain copies.
