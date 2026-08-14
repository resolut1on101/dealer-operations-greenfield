# Package 03 — Frozen Canonical Product Reference

This document is an audit description of the internal reference derived from `paket.xlsx`. It is **not** an upload template and is not a user-facing Product Master.

- Scope: `1237`
- Reference version: `paket-51fb373c-v1`
- Evidence SHA-256: `51fb373ca178b68a8ddd29a6ea8f65f54162137c78aaccfb9b7f93805ffffdf2`
- Evidence: `331` operations, `84` raw codes, `59` stable directed relations, `36` canonical products
- Runtime upload dependency: **none** for `paket.xlsx`

## Canonicalization contract

`canonical quantity = raw quantity × numerator / denominator`.

For `STANDARD` products, split codes collapse to the main/largest stock code. For `HIGH_ALCOHOL`, direction is intentionally reversed: case/multipack codes collapse into the single/retail canonical code. Exact quantity is used for every calculation; rounding is presentation-only.

The supplied Sellout evidence classifies observed conversion components as `Bira` or `Distile`. In the supplied data, Bira conversion edges use `KL↔KL`, `TVA↔TVA` or `KAS↔KAS`; Distile uses `KL↔ADT`. The unanchored `152225↔152316` component is therefore classified `HIGH_ALCOHOL` by the exact `KL→ADT` reference signature; `150783/151942/151943` is classified `STANDARD` by its `TVA↔TVA` signature.

## Frozen mappings

| Policy | Canonical code | Raw code → canonical factor | Policy basis |
|---|---|---|---|
| STANDARD | `150021` | `150021 × 1`; `154525 × 1/2`; `154548 × 1/4` | `SELLOUT_BIRA` |
| STANDARD | `150137` | `150137 × 1`; `151463 × 1/2` | `SELLOUT_BIRA` |
| STANDARD | `150487` | `150487 × 1`; `151293 × 1/2`; `154505 × 1/4` | `SELLOUT_BIRA` |
| STANDARD | `150782` | `150782 × 1`; `151904 × 1/4`; `151910 × 1/2` | `SELLOUT_BIRA` |
| STANDARD | `150783` | `150783 × 1`; `151942 × 1/4`; `151943 × 1/2` | `REFERENCE_STANDARD_UOM` |
| STANDARD | `150784` | `150784 × 1`; `152046 × 1/2` | `SELLOUT_BIRA` |
| STANDARD | `151247` | `151247 × 1`; `151436 × 1/2`; `154504 × 1/4` | `SELLOUT_BIRA` |
| STANDARD | `151271` | `151271 × 1`; `151448 × 1/2`; `154012 × 1/4` | `SELLOUT_BIRA` |
| STANDARD | `151335` | `151335 × 1`; `154506 × 1/2`; `154547 × 1/4` | `SELLOUT_BIRA` |
| STANDARD | `151384` | `151384 × 1`; `152782 × 1/4`; `154510 × 1/2` | `SELLOUT_BIRA` |
| STANDARD | `151420` | `151420 × 1`; `154020 × 1/4` | `SELLOUT_BIRA` |
| STANDARD | `151428` | `151428 × 1`; `154527 × 1/2` | `SELLOUT_BIRA` |
| STANDARD | `151830` | `151830 × 1`; `154558 × 1/2`; `154559 × 1/4` | `SELLOUT_BIRA` |
| STANDARD | `151918` | `151918 × 1`; `154513 × 1/2` | `SELLOUT_BIRA` |
| STANDARD | `151961` | `151961 × 1`; `152716 × 1/2` | `SELLOUT_BIRA` |
| HIGH_ALCOHOL | `152301` | `152208 × 12`; `152301 × 1` | `SELLOUT_DISTILE` |
| HIGH_ALCOHOL | `152312` | `152221 × 6`; `152312 × 1` | `SELLOUT_DISTILE` |
| HIGH_ALCOHOL | `152313` | `152222 × 12`; `152313 × 1` | `SELLOUT_DISTILE` |
| HIGH_ALCOHOL | `152314` | `152223 × 12`; `152314 × 1` | `SELLOUT_DISTILE` |
| HIGH_ALCOHOL | `152315` | `152224 × 24`; `152315 × 1` | `SELLOUT_DISTILE` |
| HIGH_ALCOHOL | `152316` | `152225 × 24`; `152316 × 1` | `REFERENCE_KL_ADT` |
| HIGH_ALCOHOL | `152318` | `152227 × 6`; `152318 × 1` | `SELLOUT_DISTILE` |
| HIGH_ALCOHOL | `152327` | `152236 × 6`; `152327 × 1` | `SELLOUT_DISTILE` |
| STANDARD | `152422` | `152422 × 1`; `152547 × 1/2`; `152548 × 1/4` | `SELLOUT_BIRA` |
| STANDARD | `152471` | `152417 × 1`; `152471 × 1`; `152733 × 1/4` | `SELLOUT_BIRA` |
| STANDARD | `152542` | `152542 × 1`; `152710 × 1/4` | `SELLOUT_BIRA` |
| STANDARD | `152608` | `152608 × 1`; `154535 × 1/2` | `SELLOUT_BIRA` |
| STANDARD | `152644` | `152644 × 1`; `154539 × 1/2`; `154555 × 1/4` | `SELLOUT_BIRA` |
| HIGH_ALCOHOL | `152755` | `152747 × 24`; `152755 × 1` | `SELLOUT_DISTILE` |
| HIGH_ALCOHOL | `152756` | `152748 × 12`; `152756 × 1` | `SELLOUT_DISTILE` |
| HIGH_ALCOHOL | `152757` | `152749 × 12`; `152757 × 1` | `SELLOUT_DISTILE` |
| HIGH_ALCOHOL | `152758` | `152751 × 6`; `152758 × 1` | `SELLOUT_DISTILE` |
| HIGH_ALCOHOL | `152759` | `152752 × 6`; `152759 × 1` | `SELLOUT_DISTILE` |
| HIGH_ALCOHOL | `152763` | `152753 × 12`; `152763 × 1` | `SELLOUT_DISTILE` |
| HIGH_ALCOHOL | `152764` | `152754 × 6`; `152764 × 1` | `SELLOUT_DISTILE` |
| HIGH_ALCOHOL | `152949` | `152949 × 1`; `152950 × 6` | `SELLOUT_DISTILE` |

## Downstream rule

All product-related calculations must canonicalize first: Sellout, KA, FKNS, warehouse stock, stock days, target distribution, forecast, safety stock and order need. Raw split codes may remain in audit/provenance but must not create separate normal business rows.

FKNS is evaluated on canonical identity: if a point buys a split code, the canonical product is considered bought for that point. Multiple raw codes of the same canonical product still count the customer once.
