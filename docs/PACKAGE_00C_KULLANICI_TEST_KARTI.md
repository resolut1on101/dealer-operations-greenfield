# KULLANICI TEST KARTI

Paket              : `00C - First live release and safe operating base`  
Ajan                : Terra  
Zorluk / Ayar       : `YUKSEK/high`  
Canli build         : `fa5fefc`  
DB migration        : `20260809000003`  
Canli URL           : `https://7b60e51d.dealer-operations-greenfield.pages.dev`  
Yayin durumu        : `VERIFIED`  
Test kapsamı        : Onayli D0 shell, admin/viewer erisim temeli, canli build/release gorunurlugu ve yedek/restore guvenlik tabani. Alan verisi, import veya metrik testi bu paketin kapsaminda degildir.

## ON KOSULLAR

1. Live Supabase Authentication icinde iki e-posta/parola hesabi olusturun: biri yonetici, biri goruntuleyici. Her iki hesabin e-posta dogrulamasi tamamlanmis olmalidir.
2. Her yeni kullanici varsayilan olarak `viewer` olusur. Yonetici hesabinin tam Auth UUID degerini alin ve yalnizca guvenilir SQL/servis ortaminda ilk admin bootstrap islemini yapin:

   ```sql
   begin;
   set local role service_role;
   set local request.jwt.claim.role = 'service_role';
   select public.bootstrap_first_admin('<admin-auth-uuid>');
   commit;
   ```

   Basarili sonuc `admin` olmalidir. UUID'yi e-posta veya isimden tahmin etmeyin; `service_role` anahtarini tarayiciya, Cloudflare degiskenlerine veya sohbete koymayin.
3. En az iki ayrı tarayici profili veya iki cihaz hazirlayin. Ayni cihazdaki iki normal sekme, capraz-cihaz kaniti sayilmaz.
4. Yedek testi icin `docs/runbooks/backup-restore.md` icindeki DB parolasi ve baglanti dizesi adimlarini yalnizca terminalde hazirlayin. Gizli degerleri bu karta veya sohbete yapistirmayin.

## TEST-01 - Canli URL, build ve yayin durumu

Yapilacak islem     : Canli URL'yi birinci cihaz/tarayicida acin.  
Beklenen sonuc      : Sayfa acilir; ust barda `Dogrulandi`, build olarak `fa5fefc`, icerikte Paket `00C` ve DB migration `20260809000003` gorunur. `Canli testte` veya `ACCEPTED` gorunmez.  
Kontrol kaynagi     : Canli ekran.

## TEST-02 - Yonetici girisi

Yapilacak islem     : Yonetici hesabiyle giris yapin.  
Beklenen sonuc      : Erisim durumu kartinda `Yonetici` gorunur. Uygulama alan verisi veya sahte kayit gostermez; yalnizca canli kabuk ve Paket 00C durum bilgileri gorunur.  
Kontrol kaynagi     : Canli ekran ve Auth kullanici hesabi.

## TEST-03 - Goruntuleyici girisi ve yazma yuzeyi yoklugu

Yapilacak islem     : Ayri cihaz/tarayici profilinde goruntuleyici hesabiyle giris yapin.  
Beklenen sonuc      : Erisim durumu kartinda `Goruntuleyici` gorunur. Veri yukleme, yayinlama, rol degistirme veya baska bir yazma aksiyonu gosterilmez. Kabuk okunabilir durumdadir.  
Kontrol kaynagi     : Ikinci cihaz/tarayici ve canli ekran.

## TEST-04 - D0 gezinme ve responsive davranis

Yapilacak islem     : Masaustunde yan menuyu daraltip genisletin; alan gruplarindan birini secin. Telefon veya dar tarayici genisliginde hamburger menusunu acip kapatin.  
Beklenen sonuc      : Yedi D0 alan grubu gorunur; ust bar yalnizca yardimci bilgiler icerir; masaustunde daraltilmis ikon rayi, mobilde kalici olmayan drawer kullanilir. Secili alan basligi guncellenir ve yatay/dar gorunumde okunabilirlik korunur.  
Kontrol kaynagi     : Canli ekran.

## TEST-05 - Yedek/export ve local restore provasii

Yapilacak islem     : Runbook'taki `npm run backup:logical` komutuyla canli `public` data-only checkpoint olusturun; ardindan `npm run restore:rehearsal -- --environment local --input <checkpoint.sql>` komutunu calistirin.  
Beklenen sonuc      : Logical backup tamamlanir; local restore `PASS` dondurur ve Package 00 kimlik tablosunun varligi dogrulanir. Storage envanteri ayri kaydedilir; Package 00C icin envanterin bos olmasi beklenir.  
Kontrol kaynagi     : Terminal ciktiisi ve `docs/runbooks/backup-restore.md`.

## DAR REGRESYON

- Admin/viewer RLS regresyonu canli hedefte rollback transaction ile otomatik olarak PASS verdi.
- Bu paketin onceki kabul edilmis davranislara etkisi D0 kabuk/nav ve Package 00 kimlik altyapisi ile sinirlidir; alan verisi, import, metrik veya finans davranisi etkilenmez.

## KULLANICIDAN ISTENEN CEVAP

```text
TEST-01 PASS
TEST-02 PASS
TEST-03 PASS
TEST-04 PASS
TEST-05 PASS
```

Bir hata varsa:

```text
TEST-<no> FAIL - beklenen: <...>, gorulen: <...>, cihaz/tarayici: <...>, build: fa5fefc
```

Her zorunlu test PASS olmadan paket `VERIFIED` veya `ACCEPTED` degildir.
