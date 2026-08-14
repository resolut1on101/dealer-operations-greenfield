# Agent Context Map — Minimal Reading Router

**Status:** `CURRENT / BINDING`  
**Goal:** minimize Codex/agent context usage without losing authority or package safety.

## 1. Universal rule

For every task read only:

1. `README.md`
2. this file
3. the current package row/card in `KODLAMA_ASAMALI_UYGULAMA_PLANI.md`
4. the package-specific documents listed below

Do **not** preload all catalogs or `REFERANS_ARSIV/`. Open historical/reference evidence only when the current task needs a fixture, old behavior characterization, or explicit comparison.

When documents conflict, follow the authority order in `README.md` and `00_OKUMA_SIRASI_VE_GREENFIELD_KURALLARI.md`.

All agent-authored technical reports, acceptance records, audits, runbooks, architecture notes, appendices, implementation notes, changelogs, and technical handoffs are **English**. Direct user-facing UAT/test cards and instructions may remain **Turkish**.

## 2. Always-protected boundaries

- `REFERANS_REACT = C:\Users\monds\Desktop\YENI\REFERANS` — READ-ONLY.
- `REFERANS_KESAN = C:\Users\monds\Desktop\YENI\REFERANS 2\KESAN` — READ-ONLY.
- `C:\Users\monds\Desktop\YENI\VERI_REFERANS` — external READ-ONLY evidence/input area; do not commit real Excel or PII/financial source files to Git.
- Target is a separate greenfield repo. Reference code/UX is evidence only.
- Official data source is PostgreSQL/Supabase; browser state is not official data.
- Roles are only `admin` and `viewer`; no capability/scope matrix.
- From Package 00C onward, live deploy + explicit package-specific user PASS is mandatory before `ACCEPTED`.

## 3. Package → required context

| Package(s) | Read in addition to README + this map + package card |
|---|---|
| `00` | `00_OKUMA_SIRASI_VE_GREENFIELD_KURALLARI.md`, `REFERANS_UYGULAMA_KONUMLARI.md`, current repo `TECH_STACK_DECISION.md` / `PACKAGE_00_ACCEPTANCE.md` if present |
| `00A` | `00_OKUMA_SIRASI_VE_GREENFIELD_KURALLARI.md`, `REFERANS_UYGULAMA_KONUMLARI.md`, `SUPERSEDED_KARAR_HARITASI.md`; inspect both reference apps read-only |
| `00B`, `00C` | `00_OKUMA_SIRASI_VE_GREENFIELD_KURALLARI.md`, `KULLANICI_KABUL_VE_CANLI_TEST_PROTOKOLU.md`, current D0/UI spec; `VERITABANI_YENIDEN_TASARIM_PLANI.md` only for environment/recovery boundary |
| `01`, `01U` | `VERITABANI_YENIDEN_TASARIM_PLANI.md`, decision register §22 Package 01, `KULLANICI_KABUL_VE_CANLI_TEST_PROTOKOLU.md` |
| `02`, `02U` | decision register §§1–2 + §22 Package 02; matrix customer/org rows |
| `03` | backend/internal canonical product normalization + frozen paket reference; decision register §5 + §22 Package 03; matrix `PRD-*`; no Product Master/Ürünler executor route |
| `03U` | `CANCELLED_NOT_REQUIRED`; no standalone Product Master/Ürünler screen |
| `03A`, `03AU` | `PACKAGE_03A_REAL_DATA_EVIDENCE.md`, `PACKAGE_03A_ACCEPTANCE.md`; for active 03AU work also `PACKAGE_03AU_IMPLEMENTATION_REPORT.md` + `PACKAGE_03AU_KULLANICI_TEST_KARTI.md`; decision register §6; `STOK_METRIK_KATALOGU.md` current-stock section; matrix `STK-*` |
| `04`, `04U` | decision register §3; matrix `EVT-*`, `ACT-*`, `TGT-*`; stock catalog only if demand dependency is touched |
| `04A` | decision register §19; matrix `STL-*` |
| `04B`, `04BU` | decision register §21; matrix/report rows relevant to Sellout comparison; do not load financial catalog unless a financial metric is explicitly requested |
| `05`, `05U` | decision register §4; matrix `FKNS-*`; product-family dependency from §5 only |
| `06`, `06U` | decision register §8; `STOK_METRIK_KATALOGU.md`; matrix `FCST-*`, `STK-*`, `SS-*`, `REQ-*`, `ORD-*`, `RISK-*` |
| `06A`, `06AU` | decision register §7; stock catalog Commercial Stock section; matrix `CST-*` |
| `07`, `07U` | decision register §9; matrix `FIN-000/001/001A..001D/002` and cancellation contracts |
| `07A` | decision register §20 + §22 Package 07A; matrix `ORDOP-*` |
| `07B`, `07BU` | decision register §20; matrix `ORDOP-*`, `OPS-DOC-*`, shipping/report contracts |
| `08`, `08U` | decision register §12; financial catalog instrument/current-risk sections; matrix `COLL-*`, financial instrument rows |
| `08A` | decision register §11–12; matrix `OPS-DOC-*`; official-collection reconciliation tests |
| `08B`, `08BU` | decision register §22 Package 08B; matrix `NOTEPRINT-*`; user-approved print/UI spec for `08BU` |
| `09`, `09U` | decision register §12 Purchase routing; financial catalog economic-vs-cash collection rules |
| `10`, `10U` | decision register §§13–14 + §18; financial catalog core financial sections; matrix `FIN-*`, allocation/aging rows |
| `10A`, `10AU` | decision register §20 + Package 10A; matrix `FCTL-*`, `OPS-DOC-*`, relevant `FIN-*` |
| `11`, `11U` | decision register §10; matrix `MAN-*`, `DQ-*`; relevant affected-domain doc only |
| `12A` | decision register §§13–14 + §18; `FINANSAL_ANALIZ_VE_RAPOR_KATALOGU.md`; matrix financial rows |
| `12B` | decision register §§15–17; financial catalog score/limit/scorecard; matrix corresponding `FIN-*` |
| `12C` | `FINANSAL_ANALIZ_VE_RAPOR_KATALOGU.md` cohort/migration/concentration sections; relevant `FAN-*` rows |
| `12D` | financial catalog forecast/signal/scenario; matrix `FAN-*` + scenario definitions |
| `12E`, `12EU` | financial catalog artifact/report contract + matrix `RPT-*` / report rows; user-approved D7 report spec for `12EU` |
| `12F` | financial catalog action/outcome/attribution; relevant `FAN-*`; do not infer causality outside approved contract |
| `13`, `13U` | `SISTEM_HESAPLAMA_MATRISI.md` central execution + `MET-*`; decision register Package 13; load domain catalog only for metric families touched |
| `14`, `14U` | `AI_MEVCUT_DURUM_VE_GELISTIRME_PLANI.md`, matrix `AIENG-*`, decision register Package 14; load metric/domain doc only for tools/claims touched |
| `15` | top-level rules, decision register current greenfield sections, all package acceptance evidence needed for integration; `CUT-*` only as historical safety evidence, not target route strategy |
| `15U` | current approved UI specs + top-level UX rules + UAT protocol; domain catalogs only if a display ambiguity requires them |
| `16` | top-level rules, UAT protocol, DB/import plan, environment/backup/recovery runbooks, final package acceptance evidence |

## 4. Query-oriented shortcuts

- **Customer/rep/SSM/channel:** decision register §§1–2 → matrix `CUS-*`/`ORG-*`.
- **Product/LPU/family:** decision register §5 → matrix `PRD-*`.
- **Sellout/FKNS:** decision register §§3–4 → matrix `EVT-*`/`ACT-*`/`FKNS-*`.
- **Stock/forecast/SS/order:** decision register §§6–8 → stock catalog → relevant matrix families.
- **Invoice/current account/collections:** decision register §§9–18 → financial catalog → relevant `FIN-*`/`COLL-*`.
- **Reports/artifacts:** financial catalog report sections → matrix report families.
- **AI:** AI plan → matrix `AIENG-*` → only the domain metric docs used by the request.
- **Manual correction/conflict:** decision register §10 → matrix `MAN-*`/`DQ-*` → affected domain only.

Product-related user-facing work continues in operational packages `03A/03AU`, Sellout, FKNS, and planning. The binding router must not direct a future executor to Product Master/Ürünler screen development.

## 5. Historical/superseded handling

- `SUPERSEDED_KARAR_HARITASI.md` maps obsolete directives to current equivalents.
- `CUT-*` legacy route/canary/retirement rows in the calculation matrix are historical registry evidence under the 2026-08-09 greenfield override. Do not reactivate them as mandatory target architecture.
- `REFERANS_ARSIV/` is never a default context source. Use only for a named fixture/characterization question, and current binding documents win on conflict.

## 6. Context-budget discipline

- Prefer section/range reads over full-file reads for large catalogs.
- Do not paste entire source datasets or 10K rows into AI context.
- Do not reread unchanged global rules repeatedly inside one task.
- Summaries may reduce prose, but **must not replace exact formulas, thresholds, metric IDs, source-contract fields, acceptance gates, or user-approved decisions**.
- When a needed detail is not in the loaded sections, fetch that exact section rather than guessing.
