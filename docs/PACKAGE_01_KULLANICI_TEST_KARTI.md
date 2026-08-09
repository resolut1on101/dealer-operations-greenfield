# Package 01 Kullanıcı UAT Kartı

Paket: `01 - Import, reconciliation ve publication`  
Paket durumu: `LIVE_TESTING`  
UAT durumu: `HAZIR — kullanıcı testi bekleniyor`  
Kabul durumu: `ACCEPTED DEĞİL`

## Başlangıç kaydı

- Canlı hedef: `dealer-operations-live`.
- Canlı migration seviyesi: `20260809000008`.
- Uygulama: [canonical Pages URL](https://dealer-operations-greenfield.pages.dev).
- Public frontend smoke: `PASS` — kullanıcı canonical proje URL'sini açarak doğruladı.
- Hash'li deployment URL (`https://94396efa.dealer-operations-greenfield.pages.dev`): erişilemedi. Bu, canonical URL çalıştığı için non-blocking gözlemdir; yeni deploy gerektirmez.
- Package 01, aşağıdaki zorunlu UAT kontrollerinin tamamı kullanıcı tarafından `PASS` verilmeden `ACCEPTED` yapılmayacaktır.

## Test ön koşulları

- Admin rolüyle giriş yapılmış bir tarayıcı.
- Viewer rolüyle giriş yapılmış ikinci tarayıcı veya cihaz.
- En az 10.000 satırlı gerçek Excel kaynak dosyası ve kaynak kontrol toplamları (satır sayısı ile ilgili sayısal toplamlar).
- Test sırasında kullanılacak ikinci, farklı bir dosya veya aynı dosyanın kopyası.
- Test sonuçlarını bu kartın sonundaki kayda yazacak yetkili kullanıcı.

## UAT kontrolleri

| No | Kullanıcı adımı | Beklenen sonuç | Sonuç |
|---|---|---|---|
| UAT-01 | Canonical Pages URL'yi açın ve admin olarak giriş yapın. | Uygulama açılır; sürüm bilgisi `LIVE_TESTING`, Package `01`, DB migration `20260809000008` görünür. | `BEKLIYOR` |
| UAT-02 | 10K+ Excel dosyasını içe aktarmaya başlayın. | Kaynak dosya doğrulanır, batch oluşturulur ve ilerleme/sonuç görünür; hata varsa satır düzeyinde anlaşılır biçimde gösterilir. | `BEKLIYOR` |
| UAT-03 | Kaynak satır sayısı ve belirlenen kontrol toplamlarını import/reconciliation sonucu ile karşılaştırın. | Kaynak ve kabul edilen kayıt sayıları ile kontrol toplamları eşleşir; reddedilen satırlar varsa gerekçeleri görünür. | `BEKLIYOR` |
| UAT-04 | Yükleme sürerken tarayıcıyı kapatın veya bağlantıyı kesin; sonra aynı admin hesabıyla yeniden açın ve devam ettirin. | Aynı batch güvenli biçimde devam eder ya da durumuyla birlikte tekrar başlatılabilir; çift yayın veya veri kaybı oluşmaz. | `BEKLIYOR` |
| UAT-05 | Tamamlanan aynı dosyayı yeniden yüklemeyi deneyin. | Yinelenen kaynak güvenli biçimde tanınır/reddedilir; ikinci aktif yayın veya mükerrer iş kaydı oluşmaz. | `BEKLIYOR` |
| UAT-06 | Başarılı batch'i yayınlayın; ardından sayfalı detay görünümünde ilk, orta ve son sayfalardan kayıtları kontrol edin. | Yayın tek ve atomiktir; görünen veri yalnız yeni aktif sürümdendir; sayfalar tutarlı sonuç verir. | `BEKLIYOR` |
| UAT-07 | İkinci tarayıcı/cihazda viewer hesabıyla aynı veriyi açın. | Viewer yayınlanmış veriyi okuyabilir; import başlatma, reconcile, publish veya kaynak dosya değiştirme işlemleri yapamaz. | `BEKLIYOR` |
| UAT-08 | Hatalı veya eksik bir dosya ile publish aşamasına kadar ilerlemeyi deneyin. | Publish engellenir; önceki aktif yayın korunur ve kullanıcıya anlaşılır hata bilgisi verilir. | `BEKLIYOR` |
| UAT-09 | Test başı ve sonundaki Storage/DB/egress tüketimini kaydedin. | Kullanım değişimleri test batch'leriyle izlenebilir; beklenmeyen büyüme veya erişim hatası yoktur. | `BEKLIYOR` |

## Sonuç kaydı

Test tarihi: `________________`  
Test eden: `________________`  
Kullanılan kaynak dosya(ları): `________________`  
Kaynak satır sayısı / kontrol toplamları: `________________`  
Storage/DB/egress gözlemi: `________________`  
Genel sonuç: `PASS / FAIL`  
Notlar ve hata kanıtı: `________________`

Tüm zorunlu maddeler `PASS` olmadan Package 01 kabul edilmez. Açık kullanıcı `PASS` kaydı sonrasında ayrı kabul kaydı hazırlanır; bu kart tek başına `ACCEPTED` anlamına gelmez.
