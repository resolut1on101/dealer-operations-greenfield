# Package 03 — Canonical Product Normalization Fix Report

## Result

`SOURCE_FIXED_PENDING_CANONICAL_RUNTIME_AND_USER_PASS`

This source correction implements the clarified product split/combine business rule without creating a standalone Product Master UI. It does **not** claim LIVE acceptance. The correction requires canonical-repo runtime/database gates, forward migration deployment, and explicit user PASS before it can be marked accepted.

## Exact evidence used

| Evidence | Business role | Rows | SHA-256 |
|---|---|---:|---|
| `paket.xlsx` | one-time split/combine reference; **not uploadable** | 331 | `51fb373ca178b68a8ddd29a6ea8f65f54162137c78aaccfb9b7f93805ffffdf2` |
| `Sellout Raporu (5).xlsx` | Geleneksel channel runtime sales | 12,666 | `cd937d02c0fdf6eda155593ab5d4e5ca43ccce60cb0352a6706e43544fac6c68` |
| `İrsaliye Listesi (2).xlsx` | Modern/KA channel runtime sales | 1,587 | `eefa6f383482ceec1931a61474d91d8f2bcc7c1216daaa909a38058b25ca3cab` |

Independent re-read of the uploaded `paket.xlsx` reproduced exactly **59 stable directed relations** from **331 operations**. The 59 seeded relations in migration `00017` match the workbook source/target codes, reduced quantity bases, UOMs and observation counts exactly; no relation is missing or extra.

The conversion graph contains 36 connected components. Sellout evidence classifies 19 observed components as `Bira`, 15 as `Distile`, and 2 are not observed in Sellout. No observed component mixes `Bira` and `Distile`. The two unobserved components have distinct exact UOM signatures: `152225↔152316` is `KL→ADT` and is assigned the high-alcohol reverse policy; `150783/151942/151943` is `TVA↔TVA` and is assigned the standard policy.

## Implemented business rules

1. `paket.xlsx` is retired as a runtime/user-upload source. Existing historical evidence can remain for audit, but no new `PRODUCT_CONVERSION` publication is accepted.
2. The workbook evidence is frozen into versioned internal reference `paket-51fb373c-v1`.
3. All 84 referenced raw codes normalize to 36 canonical business products using exact rational factors.
4. **Standard/Bira:** split codes collapse into the main/full canonical code. Example: `154525 → 1/2 × 150021`, `154548 → 1/4 × 150021`.
5. **High alcohol/Distile:** direction is reversed. Case/multipack codes collapse into the single/retail canonical code. Example: `152224 → 24 × 152315`.
6. Raw codes outside the frozen reference remain identity mappings; they are never silently dropped.
7. FKNS uses canonical identity. A point buying a split code fulfills the same canonical product target, and a point buying multiple raw codes of the same canonical product is counted once.
8. Sellout, KA, warehouse stock, stock days, target allocation, forecast, safety stock and order need are contractually downstream of canonical code/quantity normalization.
9. Exact quantity is calculation truth. Example: `10 + 1/2 + 1/4 = 10.75`; all calculations use `10.75`. A UI may display `11`, but display rounding cannot feed back into any calculation.
10. Canonical litre-per-unit is internal. Runtime Sellout/KA positive rows are normalized to canonical quantity before `Σ litre / Σ canonical quantity`; Sellout remains higher-priority evidence than KA. Missing positive evidence is `NULL`, never zero.
11. Product conversion/LPU/reference helpers are internal calculation infrastructure; normal authenticated viewers do not receive Product Master/variant/LPU RPC access.
12. Package `03U` is cancelled/not required. Product-related user surfaces belong to operational modules such as warehouse stock, Sellout and FKNS.

## Forward migration

New migration:

`supabase/migrations/20260814000017_package_03_canonical_product_normalization.sql`

SHA-256 at source-package build time is recorded by the package build/report process.

The migration is forward-only. It does **not** rewrite accepted/applied migration `00015` or corrected freshness migration `00016`.

Main effects:

- retires active `PRODUCT_CONVERSION` contracts;
- creates versioned static reference/version, relation and canonical-mapping tables;
- seeds the exact 59 relations / 84 mappings;
- enforces exact canonical conservation across every relation;
- provides exact internal canonical code/quantity/LPU functions;
- removes normal viewer execution on legacy Product business/summary and new internal mapping/LPU functions;
- retires normal authenticated access to the old runtime `materialize_current_product_domain` path;
- changes product normalization freshness to depend on active static reference + current Sellout + current KA only;
- explicitly blocks publication of any pre-existing `PRODUCT_CONVERSION` candidate.

## Regression coverage

The corrected tests cover:

- exact packet evidence hash/counts;
- 59/331 exact relation conservation;
- 84 raw codes → 36 canonical products;
- standard split normalization;
- high-alcohol reverse normalization;
- exact `10.75` backend quantity vs presentation-only `11`;
- FKNS canonical customer uniqueness;
- identity fallback for unmapped codes;
- internal-only canonical/LPU helpers and retired Product viewer/materializer execution;
- freshness with no packet publication dependency;
- internal canonical LPU example where a `3 L` split sale (`154548 = 1/4 × 150021`) resolves to the same `12 L/canonical unit` as the main-code KA evidence.

## Verification completed in this source environment

PASS:

- uploaded evidence SHA-256 verification for packet, Sellout and KA files;
- independent `paket.xlsx` relation extraction: 331 rows / 59 stable directed relations;
- migration seed vs workbook relation comparison: exact match, 0 missing, 0 extra, 0 mismatches;
- static canonical reference regression: 84 codes → 36 canonical products, 59/331 relations conserved;
- migration and both Package 03 SQL test files lexical checks;
- `package.json` parse;
- changed TypeScript files syntax/transpile check using the available global TypeScript compiler;
- Node syntax checks for changed Package 03 scripts;
- source package contains no raw `.xlsx` evidence and no `.env`/secret file.

Not claimed as PASS in this sandbox:

- full workspace lint/typecheck/Vitest/build: local dependencies are not installed; `npm run lint` reaches workspace lint and fails because `eslint` is unavailable;
- Supabase/PostgreSQL runtime tests and concurrency: Docker/Podman/Supabase CLI/psql are unavailable in this environment.

These are still required canonical-repo release gates before LIVE mutation. Their absence here does not substitute for a runtime PASS.

## Correct integration order

1. Overlay this fixed source onto the current canonical repo without overwriting unrelated newer work.
2. Keep already-applied migrations immutable. Apply missing migration `00016` first if it is not present in that database, then apply forward correction `00017`.
3. Run canonical `lint`, `typecheck`, tests, build, `test:product-reference-static`, Package 03 PostgreSQL domain/freshness tests and concurrency tests.
4. Verify `PRODUCT_CONVERSION` is inactive and cannot be newly uploaded/published.
5. Verify current Sellout + KA publications plus the active static reference produce normalization freshness `FRESH`.
6. Verify representative standard, high-alcohol, FKNS, exact-quantity and canonical-LPU cases in PostgreSQL.
7. Only after all real invariants pass, deploy LIVE and obtain explicit user PASS.

## Acceptance boundary

The historical Package 03 production baseline remains accepted evidence. This canonicalization correction is **not** marked accepted by this report. Final correction acceptance requires canonical runtime/LIVE proof and explicit user PASS.
