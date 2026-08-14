# Package 03A — Current Warehouse Stock Implementation Report

## Result

`SOURCE_IMPLEMENTED_PENDING_CANONICAL_RUNTIME_AND_USER_PASS`

Package 03A adds the operational Malzemeler current-stock import and canonical warehouse-stock domain. It does not add the 03AU stock UI and does not claim LIVE acceptance.

## Implemented source contract

- Source kind: `WAREHOUSE_STOCK`
- Version: `1`
- Sheet: `SAPUI5 dışa aktarımı`
- Exact ordered headers: `Malzeme numarası`, `Malzeme tanımı`, `Tahditsiz kullanılabilir`
- Publication mode: `FULL_REPLACE`
- Quantity control total is a transport checksum only; mixed product quantities are never published as a business portfolio total.

## Domain behavior

Forward migration `20260814000018_package_03a_warehouse_stock.sql`:

- registers the migration-owned WAREHOUSE_STOCK source contract;
- creates immutable per-publication run/raw/canonical evidence plus an atomic current head;
- rejects non-exact source columns, invalid material identity/quantity and repeated material codes;
- applies the accepted Package 03 canonical mapping to every raw stock row;
- keeps unmapped codes as identity instead of using name similarity;
- aggregates exact canonical quantity once per canonical product;
- hides split/case raw codes from the viewer-safe current stock read surface;
- resolves litres dynamically from current canonical LPU evidence, preserving `NULL/PARTIAL` when LPU is missing;
- makes each successful WAREHOUSE_STOCK publication atomically materialize the new current snapshot in the same publication transaction;
- preserves historical publication/run evidence while the active head points only to the latest FULL_REPLACE snapshot.

## Client/source recognition

The Upload Center remains the existing Package 01 transport. For `WAREHOUSE_STOCK` only, source recognition requires the exact ordered three-column signature rather than a header superset. Filename is not used for source classification.

## Viewer boundary

Viewer-safe functions:

- `read_current_warehouse_stock()`
- `read_current_warehouse_stock_summary()`

Normal viewers receive canonical business facts only. Raw transformation tables stay behind admin RLS. Exact quantity is returned without presentation rounding; 03AU may round a copy later.

## Regression coverage

`package-03a-warehouse-stock.sql` covers:

- active exact WAREHOUSE_STOCK contract;
- standard split stock normalization (`10 + 3/4 = 10.75`);
- high-alcohol reverse case normalization;
- canonical litre calculation without display rounding;
- identity fallback with missing LPU => `NULL/PARTIAL`;
- split/case row suppression;
- FULL_REPLACE replacement with no carry-forward fabrication;
- exact-header rejection;
- duplicate material-code rejection;
- viewer isolation of raw/base tables and viewer access to the safe business surface.

CI migration checks now include `npm run test:warehouse-stock`.

## Source-environment verification

Completed:

- real workbook re-read via spreadsheet engine;
- source hash/size and exact 84-row / 84-code structure verification;
- canonical reference comparison against the accepted Package 03 snapshot;
- 53 explicitly mapped raw rows + 31 identity rows => 63 canonical business rows;
- 21 raw split/case rows collapse from normal business display;
- static Node syntax check for the new runtime test script;
- package JSON parse.

Not claimed as PASS in this sandbox:

- full lint/typecheck/unit/build, because workspace dependencies are not installed (`eslint` unavailable);
- PostgreSQL/Supabase runtime migration test, because no local Supabase runtime is available here.

These are canonical-repo release gates, not reasons to change the Package 03A business design.
