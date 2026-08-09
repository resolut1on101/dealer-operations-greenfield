# KULLANICI TEST KARTI

Paket              : `00C — First live release and safe operating base`  
Ajan                : Terra  
Zorluk / Ayar       : `YÜKSEK/high`  
Canlı build         : `8b05985`  
DB migration        : `20260809000003`  
Canlı URL           : `https://15bf1087.dealer-operations-greenfield.pages.dev`  
Yayın durumu        : `LIVE_TESTING`  
Test kapsamı        : Onaylı D0 shell, admin/viewer erişim temeli, canlı build/release görünürlüğü ve yedek/restore güvenlik tabanı. Alan verisi, import veya metrik testi bu paketin kapsamında değildir.

## ÖN KOŞULLAR

1. Live Supabase Authentication içinde iki e-posta/parola hesabı oluşturun: biri yönetici, biri görüntüleyici. Her iki hesabın e-posta doğrulaması tamamlanmış olmalıdır.
2. Her yeni kullanıcı varsayılan olarak `viewer` oluşur. Yönetici hesabının **tam Auth UUID** değerini alın ve yalnızca güvenilir SQL/servis ortamında ilk admin bootstrap işlemini yapın:

   ```sql
   begin;
   set local role service_role;
   set local request.jwt.claim.role = 'service_role';
   select public.bootstrap_first_admin('<admin-auth-uuid>');
   commit;
   ```

   Başarılı sonuç `admin` olmalıdır. UUID’yi e-posta veya isimden tahmin etmeyin; `service_role` anahtarını tarayıcıya, Cloudflare değişkenlerine veya sohbete koymayın.
3. En az iki ayrı tarayıcı profili veya iki cihaz hazırlayın. Aynı cihazdaki iki normal sekme, çapraz-cihaz kanıtı sayılmaz.
4. Yedek testi için `docs/runbooks/backup-restore.md` içindeki DB parolası ve bağlantı dizesi adımlarını yalnızca terminalde hazırlayın. Gizli değerleri bu karta veya sohbete yapıştırmayın.

## TEST-01 — Canlı URL, build ve yayın durumu

Yapılacak işlem     : Canlı URL’yi birinci cihaz/tarayıcıda açın.  
Beklenen sonuç      : Sayfa açılır; üst barda `Canlı testte`, build olarak `8b05985`, içerikte Paket `00C` ve DB migration `20260809000003` görünür. `Doğrulandı` veya `ACCEPTED` görünmez.  
Kontrol kaynağı     : Canlı ekran.

## TEST-02 — Yönetici girişi

Yapılacak işlem     : Yönetici hesabıyla giriş yapın.  
Beklenen sonuç      : Erişim durumu kartında `Yönetici` görünür. Uygulama alan verisi veya sahte kayıt göstermez; yalnızca canlı kabuk ve Paket 00C durum bilgileri görünür.  
Kontrol kaynağı     : Canlı ekran ve Auth kullanıcı hesabı.

## TEST-03 — Görüntüleyici girişi ve yazma yüzeyi yokluğu

Yapılacak işlem     : Ayrı cihaz/tarayıcı profilinde görüntüleyici hesabıyla giriş yapın.  
Beklenen sonuç      : Erişim durumu kartında `Görüntüleyici` görünür. Veri yükleme, yayınlama, rol değiştirme veya başka bir yazma aksiyonu gösterilmez. Kabuk okunabilir durumdadır.  
Kontrol kaynağı     : İkinci cihaz/tarayıcı ve canlı ekran.

## TEST-04 — D0 gezinme ve responsive davranış

Yapılacak işlem     : Masaüstünde yan menüyü daraltıp genişletin; alan gruplarından birini seçin. Telefon veya dar tarayıcı genişliğinde hamburger menüsünü açıp kapatın.  
Beklenen sonuç      : Yedi D0 alan grubu görünür; üst bar yalnızca yardımcı bilgiler içerir; masaüstünde daraltılmış ikon rayı, mobilde kalıcı olmayan drawer kullanılır. Seçili alan başlığı güncellenir ve yatay/dar görünümde okunabilirlik korunur.  
Kontrol kaynağı     : Canlı ekran.

## TEST-05 — Yedek/export ve local restore provası

Yapılacak işlem     : Runbook’taki `npm run backup:logical` komutuyla canlı `public` data-only checkpoint oluşturun; ardından `npm run restore:rehearsal -- --environment local --input <checkpoint.sql>` komutunu çalıştırın.  
Beklenen sonuç      : Logical backup tamamlanır; local restore `PASS` döndürür ve Package 00 kimlik tablosunun varlığı doğrulanır. Storage envanteri ayrı kaydedilir; Package 00C için envanterin boş olması beklenir.  
Kontrol kaynağı     : Terminal çıktısı ve `docs/runbooks/backup-restore.md`.

## DAR REGRESYON

- Admin/viewer RLS regresyonu canlı hedefte rollback transaction ile otomatik olarak PASS verdi.
- Bu paketin önceki kabul edilmiş davranışlara etkisi D0 kabuk/nav ve Package 00 kimlik altyapısı ile sınırlıdır; alan verisi, import, metrik veya finans davranışı etkilenmez.

## KULLANICIDAN İSTENEN CEVAP

```text
TEST-01 PASS
TEST-02 PASS
TEST-03 PASS
TEST-04 PASS
TEST-05 PASS
```

Bir hata varsa:

```text
TEST-<no> FAIL — beklenen: <...>, görülen: <...>, cihaz/tarayıcı: <...>, build: 8b05985
```

Her zorunlu test PASS olmadan paket `VERIFIED` veya `ACCEPTED` değildir.
