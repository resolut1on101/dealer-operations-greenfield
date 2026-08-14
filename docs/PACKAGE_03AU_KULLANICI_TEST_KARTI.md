# Package 03AU — Depo Stoku Kullanıcı Test Kartı

**Durum:** `LIVE TESTING — kullanıcı PASS bekleniyor`

Bu kart yalnız Package 03AU için kullanılmalıdır. Teknik deploy başarısı tek başına kabul değildir.

## 1. Viewer — masaüstü görünüm

1. LIVE uygulamada Viewer ile giriş yapın.
2. Sol menüden **Depo Stoku** açın.
3. Ekranda yalnız iki ana KPI olduğunu doğrulayın:
   - **Toplam Litre** — baskın ana kart,
   - **Toplam Ürün** — destek kartı.
4. Son yayın bilgisinin başlık altında kompakt metadata olarak göründüğünü; ayrı büyük snapshot bandı olmadığını doğrulayın.
5. Tablo kolonlarını soldan sağa doğrulayın:
   - Ürün Kodu
   - Ürün Adı
   - Stok
   - Litre / Birim
   - Toplam Litre
6. Ayrı bir `Durum` kolonu olmadığını doğrulayın.
7. Ürün adının görsel olarak baskın, ürün kodunun monospace ve ikincil olduğunu doğrulayın.
8. Ürün Adı başlangıçta A→Z sıralı olmalı. Ürün Adı, Stok ve Toplam Litre başlıklarından sıralamayı değiştirin.
9. Tek arama kutusunda hem ürün koduyla hem ürün adıyla arama yapın.
10. `Litre Durumu` filtresinde `Tümü / Hesaplanan / Eksik` seçeneklerini deneyin.

## 2. Viewer — ürün detayı

1. Herhangi bir ürün satırının gövdesine tıklayın.
2. Detayın Müşteriler modülündeki aynı overlay/drawer hareket mantığıyla açıldığını doğrulayın.
3. Drawer içinde:
   - Ürün Adı ana kimlik,
   - Ürün Kodu ikincil kimlik,
   - Toplam Litre baskın metrik,
   - Stok destek metriği
   olmalı.
4. `Ürün Bilgileri` bölümünde yalnız:
   - Ürün Kodu
   - Litre / Birim
   bulunmalı.
5. Viewer için `Tanımla` veya `Düzenle` mutasyon aksiyonu görünmemeli.
6. Raw mapping, split/case dönüşüm detayı veya audit geçmişi görünmemeli.
7. `X`, `Esc` ve drawer dışı alan ile kapatma davranışlarını kontrol edin.

## 3. Viewer — mobil görünüm

1. Dar mobil viewport kullanın.
2. Tablo yerine kartların geldiğini doğrulayın.
3. Kartta Ürün Adı birincil, Ürün Kodu ikincil olmalı.
4. Üst bilgi alanlarında **Stok** ve **Litre / Birim** görünmeli.
5. **Toplam Litre** kartın en altında, ortalı ve koyu lacivert vurgulu blok olarak görünmeli.
6. Her kartta tekrarlanan `Yayın` alanı **olmamalı**.
7. Kartın tamamına dokunulduğunda ürün detayı açılmalı.

## 4. Admin — eksik Litre / Birim toplu tanımlama

Bu bölüm yalnız LIVE verisinde en az bir eksik Litre / Birim ürünü varsa uygulanır.

1. Admin ile Depo Stoku açın.
2. Üstte `N ürünün Litre / Birim bilgisi eksik` uyarısını ve **Tanımla** aksiyonunu doğrulayın.
3. **Tanımla** seçin.
4. Tek modal içinde eksik ürünlerin:
   - Ürün Kodu
   - Ürün Adı
   - Litre / Birim giriş alanı
   ile listelendiğini doğrulayın.
5. Yalnız bildiğiniz bir/kaç ürünü doldurun; diğerlerini boş bırakın.
6. Kaydedin.
7. Kısmi kaydın başarılı olduğunu, tanımlanan ürünlerin eksik listeden çıktığını ve boş bırakılanların eksik kaldığını doğrulayın.
8. Eksik değerlerin `0` veya tahmini litreye dönüşmediğini doğrulayın.
9. Tüm non-zero stok ürünleri çözümlendiğinde ana **Toplam Litre** KPI değerinin backend’den güncellenmesini doğrulayın.

## 5. Admin — ürün detayından Litre / Birim düzenleme

1. Litre / Birim tanımlı bir ürünün detayını açın.
2. `Litre / Birim` yanında **Düzenle** aksiyonunu doğrulayın.
3. Küçük bir değişiklik yapıp kaydedin; drawer ve ana liste değerlerinin yeniden okunup güncellenmesini doğrulayın.
4. Mevcut değerden **%25 veya daha fazla** farklı bir değer deneyin.
5. Ek onay penceresi gelmeli; **Vazgeç** ile kayıt yapılmamalı.
6. Tekrar deneyip **Devam Et** seçin; onaylı değişiklik kaydedilmeli.
7. Viewer'a geçildiğinde bu düzenleme aksiyonu görünmemeli.

## 6. Kritik veri doğruluğu

- Eksik Litre / Birim => Toplam Litre satırında `—`; `0` değil.
- Eksik non-zero stok ürünü varsa resmi **Toplam Litre KPI** partial toplam göstermemeli; `—` kalmalı.
- Frontend görünür satırları toplayıp kendi resmi toplamını üretmemeli.
- Admin tarafından tanımlanan Litre / Birim, yeni `FULL_REPLACE` stok yüklemesinden sonra tekrar sorulmamalı.
- Stok miktarı ve litre hesapları backend'in döndürdüğü kesin değerleri temel almalı.

## Kullanıcı sonucu

Aşağıdakiler ayrı ayrı yazılmalıdır:

- **Viewer masaüstü:** PASS / FAIL
- **Viewer mobil:** PASS / FAIL
- **Viewer detay:** PASS / FAIL
- **Admin eksik Litre / Birim akışı:** PASS / FAIL / N/A
- **Admin inline düzenleme:** PASS / FAIL
- **Genel Package 03AU:** PASS / FAIL

Package 03AU yalnız **Genel Package 03AU = PASS** kullanıcı onayı sonrasında `ACCEPTED` olabilir.
