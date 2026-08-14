# Package 03A — Malzemeler Current Warehouse Stock Real-Data Evidence

## Source identity

- Source file: `Malzemeler - 2026-08-14T142321.550.xlsx`
- SHA-256: `1cee1b283cbadf7839d14c30cb0ef5cd872438b236f94139d1ad13c9dd8efc9a`
- Byte size: `7,116`
- Workbook sheet: `SAPUI5 dışa aktarımı`
- Exact ordered headers: `Malzeme numarası` → `Malzeme tanımı` → `Tahditsiz kullanılabilir`
- Data rows: `84`
- Distinct material codes: `84`
- Duplicate material codes: `0`
- Missing required values: `0`
- Negative available quantities: `0`
- Zero available quantities: `0`
- Raw quantity checksum: `11,190` (transport/reconciliation checksum only; mixed product quantities are not a business total)

The workbook contains no authoritative stock effective-date column. The timestamp in the filename is not parsed into a business fact. Runtime publication time can describe ingestion/freshness, but Package 03A does not fabricate historical stock dates.

## Package 03 canonicalization coverage

The accepted frozen Package 03 reference `paket-51fb373c-v1` is applied before warehouse-stock aggregation.

- Raw stock rows covered by an explicit frozen mapping: `53`
  - `STANDARD`: `38`
  - `HIGH_ALCOHOL`: `15`
- Raw stock rows outside the frozen reference: `31`; these remain exact identity mappings and are not name-inferred.
- Resulting canonical business rows: `63`
  - `STANDARD`: `18`
  - `HIGH_ALCOHOL`: `14`
  - `IDENTITY`: `31`
- Canonical products receiving more than one raw stock row: `14`
- Raw split/case rows suppressed from the normal business row set: `21`
- Every explicitly mapped canonical code used by this source is itself present in the current workbook; no canonical display name needs to be invented for this snapshot.

Identity fallback is intentional. Names such as multipack/case text are not sufficient evidence to create a new conversion relationship if the raw code is absent from the frozen `paket.xlsx` reference.

## Exact real-data examples

### Standard / Bira

`150021` current stock receives:

- raw `150021`: `1207`
- split `154548`: `37 × 1/4 = 9.25`
- exact canonical quantity: **`1216.25`**

`151830` current stock receives:

- raw `151830`: `235`
- split `154559`: `19 × 1/4 = 4.75`
- exact canonical quantity: **`239.75`**

No display rounding is written back into calculation truth.

### High alcohol / Distile reverse direction

`152327` (single/retail canonical product) receives:

- raw single `152327`: `47`
- case `152236`: `25 × 6 = 150`
- exact canonical quantity: **`197`**

The case code is not exposed as a separate normal stock business row.

## Current-source integrity rules

1. `WAREHOUSE_STOCK v1` is a `FULL_REPLACE` current snapshot contract.
2. Only the exact ordered three-column source signature is accepted.
3. Every source row must validate; duplicate/excluded/blocked stock rows cannot be published.
4. Repeated material codes are blocking, including conflicting repeats; the system never silently sums duplicate raw codes.
5. Raw quantity is preserved exactly and normalized with Package 03 rational factors before aggregation.
6. Missing canonical mapping uses identity; product-name similarity never creates a conversion.
7. Current business rows contain only canonical product codes. Raw split/case codes remain admin/audit evidence.
8. Litre is resolved dynamically from current Package 03 canonical LPU evidence. Missing LPU yields `NULL/PARTIAL`, never zero.
9. A later Malzemeler publication replaces the current snapshot atomically; rows absent from the new source are not carried forward as fabricated current stock.
10. Package 03A does not compute stock days, forecasts, safety stock or order need. It supplies the trusted current warehouse-stock input those packages consume later.
