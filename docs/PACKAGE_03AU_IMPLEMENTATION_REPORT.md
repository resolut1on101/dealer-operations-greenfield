# Package 03AU — Current Warehouse Stock UX/UI Implementation Report

## Status

`SOURCE_IMPLEMENTED / PENDING_RUNTIME_GATES / NOT_ACCEPTED`

The Package 03AU source implementation is based on the user-approved **v4.3** Depo Stoku design. Package 03A remains the accepted import/canonicalization source of truth. This package adds a responsive current-stock business surface and a narrowly bounded admin workflow for persistent `Litre / Birim` master corrections.

No LIVE or DEV environment mutation is performed by this source integration. Package 03AU must not be marked `ACCEPTED` until migration/runtime checks, production deployment, the package-specific user test card, and explicit user PASS are complete.

## Approved UX baseline implemented

### Desktop

- Operational grid as the primary working surface.
- Exact visible column order: `Ürün Kodu → Ürün Adı → Stok → Litre / Birim → Toplam Litre`.
- Product name is the primary visual identity; product code is secondary monospace text.
- Medium operational density with subtle zebra, hover and selected-row states.
- `Stok` and `Toplam Litre` are right aligned; `Toplam Litre` receives stronger typographic emphasis.
- One combined search field for product code + product name.
- One `Litre Durumu` filter: `Tümü / Hesaplanan / Eksik`.
- Sortable: Product Name, Stock, Total Litre. Default sort is Product Name A→Z.
- Whole-row activation opens product detail.

### Mobile

- Responsive cards derive from the same information hierarchy; there is no separate alternate product experience.
- Product name remains primary and product code remains secondary monospace text.
- `Stok` and `Litre / Birim` appear in the upper facts.
- `Toplam Litre` is the centered, dark navy emphasis block at the bottom of each card.
- Publication timestamp is intentionally not repeated on each mobile card.

### Summary/header

- Two KPI surfaces only:
  - dominant `Toplam Litre` (2/3 width on desktop),
  - supporting `Toplam Ürün` (1/3 width on desktop).
- Publication timestamp/source/`FULL_REPLACE` metadata is compact header metadata instead of a separate snapshot banner.
- The client does **not** sum visible rows to fabricate the official Total Litres KPI.

### Product detail

- Uses the same outer overlay/drawer motion grammar as the accepted Customer detail interaction (`customer-drawer-*` shell): right overlay on desktop and existing responsive behavior on small screens.
- Product Name is the primary identity; Product Code is secondary.
- Dominant metric: `Toplam Litre`; supporting metric: `Stok`.
- `Ürün Bilgileri` contains only Product Code + Litre / Birim.
- Publication metadata is a compact footer line.
- Raw split/case mapping, canonical transformation internals and audit history are not shown in the normal business drawer.

## Authoritative backend contract

Forward migration: `20260814000019_package_03au_warehouse_stock_ui.sql`.

### Persistent admin-approved Litre / Birim

New protected tables:

- `warehouse_stock_lpu_overrides`
- `warehouse_stock_lpu_override_audit`

Manual values are keyed by scope + canonical product code and survive future `WAREHOUSE_STOCK` `FULL_REPLACE` publications. They do not rewrite or weaken the accepted Package 03A publication evidence.

Effective LPU precedence for the 03AU business surface:

1. approved manual Litre / Birim override;
2. existing canonical source LPU evidence;
3. `NULL` when neither exists.

Missing LPU never becomes zero or an estimate.

### Viewer-safe reads

- `read_current_warehouse_stock_ui()`
- `read_current_warehouse_stock_ui_summary()`

The UI row surface returns canonical product identity, exact stock quantity, effective LPU, exact total litres when resolvable, explicit `RESOLVED/PARTIAL`, and source publication time.

The summary returns the authoritative business-row count and authoritative Total Litres state/value. If **any non-zero current-stock row** lacks LPU, `total_available_litres = NULL` and `total_litres_state = PARTIAL`. The frontend therefore cannot silently present a partial sum as an official portfolio total.

### Admin mutation

`set_warehouse_stock_lpu_overrides(scope, updates, confirm_large_change)`:

- requires admin via the existing server-side role assertion;
- validates positive numeric LPU values and current-scope product membership;
- supports partial multi-product saves;
- persists values independently from current stock snapshots;
- writes audit history containing old effective LPU, new LPU, actor and timestamp;
- requires explicit confirmation for changes at or above 25% of the current effective value.

Viewer cannot mutate and cannot read the override/audit base tables through RLS.

## Client implementation

New source:

- `apps/web/src/WarehouseStockWorkspace.tsx`
- `apps/web/src/lib/warehouse-stock-api.ts`
- `apps/web/src/lib/warehouse-stock-api.test.ts`

Updated integration:

- `apps/web/src/App.tsx` routes authenticated `Depo Stoku` navigation to the new workspace.
- `apps/web/src/styles.css` contains the approved scoped Package 03AU visual treatment.
- release package identifier/contracts now include `03AU`.
- default migration marker is `20260814000019`.

Admin missing-LPU workflow:

1. one page-level warning when missing LPU products exist;
2. `Tanımla` opens one batch modal;
3. admin may fill only known values and save partially;
4. saved rows are re-read from the backend and disappear from the missing set;
5. product drawer also allows inline Litre / Birim edit for Admin;
6. >=25% edits require confirmation;
7. Viewer sees no mutation controls.

## Regression coverage added

- Contract tests for `03AU` package identifier and authoritative summary `RESOLVED/PARTIAL` semantics.
- Client unit tests for row mapping, null preservation, combined search, litre-state filtering, sorting, and 25% confirmation threshold.
- PostgreSQL test `package-03au-warehouse-stock-ui.sql` covers:
  - missing LPU => row `NULL/PARTIAL`;
  - partial official Total Litres => `NULL`;
  - admin persistent LPU definition;
  - authoritative resolved total after completion;
  - persistence across a later `FULL_REPLACE` publication;
  - 25% server-side confirmation gate;
  - audit recording;
  - viewer business read access;
  - viewer isolation from override/audit internals;
  - viewer mutation rejection.

Runtime runner: `npm run test:warehouse-stock-ui`.

## Sandbox source-integration verification

Actually performed against this source snapshot:

- input snapshot SHA-256 rechecked: `e236c99405221f5fb5ad9fe9438296deb1871895c8e98f3ca4e85cf15c6cd6b6`;
- TypeScript/TSX syntax transpilation PASS for all new/modified TS/TSX files using the available TypeScript compiler;
- new Node runtime test runner syntax (`node --check`) PASS;
- `package.json` and `package-lock.json` JSON parse PASS;
- Package 03AU scoped CSS brace/static integrity PASS;
- migration and SQL test delimiter/static integrity PASS;
- explicit source invariants PASS: exact table column order, two KPI surfaces, no `Durum` column, no repeated mobile publication field, Customer drawer shell reuse, no client-side official Total Litres sum, persistent override/audit contract, server-side 25% gate.

Not claimed as runtime PASS in this sandbox:

- PostgreSQL/Supabase test execution: attempted runner stopped before database work because Docker CLI is not installed in this environment;
- full workspace lint/typecheck/unit/build: workspace dependencies are not present in this extracted snapshot, so dependency-backed gates remain canonical-repo release work.

No LIVE or DEV mutation was performed.

## Acceptance boundary

Source integration alone is not acceptance.

Required remaining gates:

1. install/use canonical workspace dependencies and run lint/typecheck/unit/build;
2. run migration chain and Package 03AU PostgreSQL test against a disposable/local Supabase runtime;
3. review migration/runtime output for regression against accepted Package 03A;
4. apply migration `20260814000019` to LIVE only through the approved release process; DEV remains untouched unless explicitly authorized;
5. deploy the resulting web build;
6. execute `PACKAGE_03AU_KULLANICI_TEST_KARTI.md` on LIVE as Admin and Viewer;
7. receive explicit user PASS.

Until those gates complete, status remains:

`PACKAGE03AU_SOURCE_IMPLEMENTED / NOT_ACCEPTED`
