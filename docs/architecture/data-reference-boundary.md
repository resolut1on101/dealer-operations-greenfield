# Dış Veri Referans Sınırı

**Durum:** Paket 00 dokümantasyon kaydı. Bu belge import motoru veya veri modeli tanımlamaz.

Paket 01 için dış, READ-ONLY veri referansı aşağıdaki repo-dışı Windows yoludur:

`C:\Users\monds\Desktop\YENI\VERI_REFERANS`

Bu yol uygulama repository’sinin parçası değildir. Uygulama reposuna kopyalanmaz; gerçek Excel dosyaları Git’e eklenmez; hiçbir gerçek dosya değiştirilmez, yeniden kaydedilmez veya normalize edilmiş haliyle kaynağın üzerine yazılmaz.

## Klasör sözleşmesi

| Klasör | İzin verilen amaç |
|---|---|
| `00_ORIJINAL_EXCEL_READONLY` | Gerçek Excel kaynakları; yalnız salt-okunur inceleme/karakterizasyon. |
| `01_ANONIM_TEST_ORNEKLERI` | Yalnız anonim veya sentetik küçük fixture. |
| `02_BUYUK_YUK_TESTLERI` | Paket 01 sırasında üretilecek sentetik 10K/25K/50K yük test Excel’leri. |
| `03_EDGE_CASE_FIXTURES` | Kontrollü hata ve sınır senaryoları. |
| `04_KONTROL_TOPLAMLARI` | Kaynak SHA256, sheet, satır/kolon sayısı ve exact kontrol toplamı manifestleri. |

`04_KONTROL_TOPLAMLARI` yalnız doğrulama manifestidir; gerçek kaynak içeriği veya business data kopyası değildir.

## Gelecek Paket 01 sınırı

Kaynak dosya adı hiçbir iş kuralı değildir. Kaynak türü yalnız sheet, kolonlar ve version-controlled source-contract üzerinden belirlenecektir. Paket 01, bu dış referansı kullanabilir; ancak bu Paket 00 kaydı import motoru, parser, database import tablosu, source-contract ya da test Excel üretimi oluşturmaz.

Gerçek Excel dosyaları local/dev/live resmî business data kaynağı değildir. Resmî business data, ancak ileride Package 01’in doğrulanmış import/publish akışı sonunda Supabase PostgreSQL’de oluşacaktır.
