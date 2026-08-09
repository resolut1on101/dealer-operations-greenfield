# External Data Reference Boundary

**Status:** Package 00 documentation only. This document does not define an import engine or data model.

External read-only data reference for future Package 01 work:

`C:\Users\monds\Desktop\YENI\VERI_REFERANS`

This path is outside the application repository. Never copy real Excel files into Git; never modify, re-save, normalize, or overwrite the originals.

## Folder contract

| Folder | Allowed purpose |
|---|---|
| `00_ORIJINAL_EXCEL_READONLY` | Real Excel sources; read-only inspection/characterization only. |
| `01_ANONIM_TEST_ORNEKLERI` | Small anonymized or synthetic fixtures only. |
| `02_BUYUK_YUK_TESTLERI` | Synthetic 10K/25K/50K load-test workbooks created during Package 01. |
| `03_EDGE_CASE_FIXTURES` | Controlled error and boundary-condition fixtures. |
| `04_KONTROL_TOPLAMLARI` | Validation manifests: source SHA256, sheet, row/column counts, and exact control totals. |

`04_KONTROL_TOPLAMLARI` stores validation evidence only, never copied real business data.

## Future Package 01 rules

- A filename is never a business rule.
- Identify a source type from sheet structure, columns, and a version-controlled source contract.
- Real Excel files are evidence/reference inputs, not the official `local`, `dev`, or `live` source of truth.
- Official business data exists only after a future validated Package 01 import/publish flow writes and publishes it in Supabase PostgreSQL.

This Package 00 record does **not** authorize early implementation of parsers, import tables, source contracts, or test workbook generation.
