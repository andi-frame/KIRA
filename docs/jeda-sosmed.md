# Jeda sosmed

Fitur opsional di aplikasi Android. Sebelum aplikasi media sosial yang dipilih pengguna terbuka, KIRA menampilkan satu kartu layar
penuh. Tujuannya mengubah momen "buka Instagram tanpa sadar" menjadi satu dorongan kecil ke kebiasaan yang sudah direncanakan.

## Kartu

| Kartu | Kapan (bawaan, bisa diubah) | Isi | Tombol |
|---|---|---|---|
| Rencana hari ini | 05.00-10.59 | olahraga hari ini, tiap waktu makan yang belum tercatat dengan contoh menu, komponen, dan alasannya (angka dari `core_calc/planner.py`), jam tidur | Buka rencana |
| Catat hari ini dulu? | 19.00-23.59 | waktu makan dan olahraga yang belum tercatat. Bila semuanya sudah tercatat, tidak ada kartu | Catat sekarang (ke chat) |
| Waktunya bersiap tidur | 21.30-03.59 | jam tidur dan bangun dari rencana | Buka rencana |
| Sudah sempat cek? | kapan saja, sekali sehari | hanya bila saran cek ke dokter atau puskesmas sudah beberapa hari belum dijawab; bisa dimatikan | Lihat saran cek |

Kartu yang berlaku bersamaan (mis. 22.00: catat + tidur) tampil bertumpuk dalam satu layar.

## Fun fact kesehatan (opsional, mati secara bawaan)

Bila dinyalakan, setiap kali aplikasi pilihan dibuka (di luar masa bebas dan hari yang dilewati) tampil kartu "Tahukah kamu?"
berisi satu fakta kesehatan singkat beserta sumbernya, ditambah ajakan memutuskan dengan sadar: lanjut atau tidak. Faktanya
berputar berurutan (14 fakta) supaya tidak berulang. Kartu ini tidak punya tombol aksi dan tidak dibatasi tiga kali sehari,
karena penggunalah yang memintanya; "Lewati sampai besok" dan masa bebas tetap berlaku. Daftar faktanya konstanta di aplikasi
(`jeda_facts.dart`) dan dikirim ke Android bersama pengaturan, sehingga tetap muncul walau rencana tidak bisa dimuat (tanpa
sinyal). Sumber tiap fakta ada di `docs/sumber-angka-klinis.md`.

## Masa bebas setelah kartu ditutup (dapat dimatikan)

Secara bawaan, setelah "Lanjut" ditekan semua aplikasi pilihan bebas dibuka selama 15/30/60 menit. Saklar "Setelah kartu ditutup,
bebas buka sosmed selama" bisa dimatikan: kartu lalu muncul lagi setiap kali sosmed dibuka. Batas tiga kali sehari per jenis
kartu terjadwal tetap berlaku; fun fact tidak dibatasi.

## Izin terkunci "Dikontrol oleh setelan terbatas"

Android 13 ke atas mengunci izin sensitif untuk aplikasi yang dipasang dari berkas APK (bukan dari toko aplikasi), dan Android 15
memperluasnya ke akses penggunaan serta tampil di atas aplikasi lain ([Android Authority](https://androidauthority.com/android-15-restricted-settings-sideloading-3481098)).
Aplikasi tidak bisa membukanya sendiri; pengguna melakukannya sekali: Info aplikasi > titik tiga (⋮) > **Izinkan setelan terbatas**
> konfirmasi PIN/sidik jari, lalu kembali dan tekan Izinkan lagi. Bila menu itu belum ada, tekan Izinkan sekali sampai muncul
pesan terkunci, tutup, lalu buka Info aplikasi lagi. Layar pengaturan menampilkan langkah ini bila izin belum lengkap, dengan tombol
"Buka Info aplikasi". Aplikasi dari Google Play tidak terkena kunci ini.

## Status penjagaan (cara mencari tahu mengapa kartu tidak muncul)

Di layar Jeda sosmed ada kartu **Status penjagaan** yang dimuat ulang tiap 3 detik: apakah layanan berjalan, aplikasi apa yang
terakhir terdeteksi (dan kapan), apa yang terjadi pada pembukaan aplikasi pilihan yang terakhir, dan **seandainya aplikasi pilihan
dibuka sekarang, kartu apa yang tampil atau mengapa tidak ada** (di luar jam kartu, masa bebas, dilewati sampai besok, jatah
tiga kali habis, semua sudah tercatat, atau isi kartu belum sampai). Bila KIRA belum dikecualikan dari penghemat baterai, ada
peringatan dengan petunjuk per merek (Xiaomi, Oppo/Realme, Vivo, Huawei, Samsung) dan tombol "Atur penghemat baterai".
Galat terakhir dari layanan ikut ditampilkan. Aplikasi sosmed yang dibuka sebelum layanan hidup tidak akan menampilkan apa pun,
jadi cek baris pertama dulu.

Fun fact menyala sejak Jeda pertama kali dinyalakan (bisa dimatikan), karena kartu terjadwal hanya berlaku di jam tertentu dan
tanpa itu sebagian besar hari tidak ada kartu sama sekali. Jatah tampil baru dihitung setelah jendela kartu berhasil dipasang,
jadi kegagalan memasang tidak menghabiskan jatah hari itu.

## Aturan agar tidak mengganggu

- Mati sampai pengguna menyalakan, memilih aplikasi, dan memberi dua izin.
- Tombol "Lanjut ke Instagram" baru aktif setelah 3 detik; setelah ditekan, semua aplikasi bebas selama 15/30/60 menit (pilihan pengguna).
- "Lewati sampai besok" mematikan kartu untuk hari itu (hari berganti pukul 04.00 supaya tidur larut tidak terhitung dua hari).
- Satu jenis kartu tampil paling banyak 3 kali sehari, info "sudah sempat cek" sekali.
- Tombol kembali menuju layar utama (inti "jeda"-nya). Berpindah ke aplikasi lain (mis. Home) menutup kartu.
- Kalimat kartu mengikuti aturan produk: tidak mendiagnosis, tidak menyebut obat, tidak memakai kata "aman" (diuji).

## Cara kerja

```
Flutter (Dart)                                   Android (Kotlin)
JedaController ──apply(settings, payload)──▶ JedaPlugin ─▶ JedaStore (SharedPreferences pribadi)
  menyusun kartu dari /plan/today,                         └▶ JedaService (layanan latar depan, ikon senyap)
  /plan/week, dan saran cek                                      tiap 0,7 dtk baca UsageStatsManager:
  (jeda_content.dart, fungsi murni)                              aplikasi pilihan baru di depan?
                                                                 └▶ JedaDecider.due(...) ▶ JedaOverlay (jendela overlay)
```

- **Mengapa jendela overlay, bukan Activity:** tidak bergantung pada aturan peluncuran Activity dari latar (yang berbeda antarversi
  dan pabrikan), tidak membuat tugas baru yang mengubah urutan aplikasi, dan muncul seketika. Catatan: Android 15 mempersempit
  pengecualian izin overlay hanya untuk *memulai layanan latar depan* dari latar (harus sudah ada jendela overlay yang terlihat);
  layanan Jeda dimulai dari aplikasi yang sedang terbuka atau dari siaran boot, bukan dari latar biasa
  ([sumber](https://developer.android.com/about/versions/15/behavior-changes-15)).
- **Mengapa kartu disiapkan Flutter:** hanya Dart yang punya akses ke rencana. Kartu pagi disiapkan untuk hari ini dan 6 hari ke depan
  (per tanggal), jadi tetap benar walau KIRA tidak dibuka beberapa hari. Kartu catat memuat waktu pemeriksaan; bila lebih dari 5 jam
  atau beda hari, Android memakai ajakan umum alih-alih mengklaim "belum tercatat". Info cek yang lebih dari 3 hari tidak ditampilkan.
- Isi kartu disusun ulang tiap KIRA dibuka kembali, tiap ada catatan baru lewat chat, dan tiap pengaturan berubah.
- Setelah ponsel menyala ulang atau KIRA diperbarui, `JedaBootReceiver` menyalakan layanan lagi bila masih diaktifkan dan izin ada.
- Tombol kartu membuka KIRA di layar yang diminta (`/chat`, `/plan`, `/check`) lewat `takeLaunchRoute`.

## Batasan yang jujur

- **Hanya Android.** iOS tidak mengizinkan aplikasi tahu aplikasi lain yang sedang dibuka (Screen Time API butuh entitlement khusus
  Apple); web tidak bisa sama sekali. Di sana layar pengaturan menjelaskannya.
- **Belum diuji di perangkat atau emulator.** Logika pemilihan kartu (14 uji JVM), penguraian JSON (5 uji JVM), isi kartu, pengaturan,
  dan layar (uji Flutter) otomatis lulus dan APK debug berhasil dibangun, tetapi pembacaan aplikasi di depan dan jendela overlay butuh
  ponsel sungguhan. Daftar uji manual di bawah.
- Ada jeda kurang dari satu detik: aplikasi sosmed bisa terlihat sekilas sebelum kartu menutupinya (pemantauan berkala, bukan pencegat).
- Sebagian pabrikan (Xiaomi, Oppo, Vivo, Huawei) mematikan layanan latar secara agresif; pengguna perlu mengecualikan KIRA dari
  penghemat baterai. Layanan tidak bisa mengubahnya sendiri.
- Google Play membatasi izin "akses penggunaan" dan jenis layanan latar depan `specialUse`; untuk rilis publik perlu deklarasi
  penggunaan. Untuk kompetisi dan pengujian langsung (sideload) tidak ada masalah.
- Pengguna yang mencabut izin di pengaturan Android membuat layanan berhenti sendiri pada pengecekan berikutnya.

## Uji manual di ponsel Android (8.0 ke atas)

1. Pasang APK, masuk, buka Profil > Jeda sosmed, nyalakan.
2. Berikan "Akses penggunaan" dan "Tampil di atas aplikasi lain" lewat tombol Izinkan; kembali ke KIRA. Status berubah menjadi "Menjaga N aplikasi".
3. Tekan tombol contoh (Pagi, Catat, Tidur, Cek): kartu tampil di atas KIRA; "Tutup contoh" menutupnya.
4. Ubah jam "Rencana pagi" agar mencakup jam sekarang, tutup KIRA, buka Instagram: kartu pagi muncul sebelum atau sesaat setelah Instagram.
5. Tahan 3 detik, tekan "Lanjut ke Instagram": Instagram bisa dipakai; buka lagi dalam masa jeda tidak memunculkan kartu.
6. Tekan tombol kembali pada kartu: kembali ke layar utama, bukan ke Instagram. Tekan Home: kartu hilang.
7. "Catat sekarang": KIRA terbuka di chat. "Buka rencana": terbuka di Rencana.
8. "Lewati sampai besok": tidak ada kartu lagi sampai pukul 04.00.
9. Matikan saklar atau keluar akun: ikon senyap di status bar hilang dan kartu tidak muncul lagi.
10. Mulai ulang ponsel dengan Jeda menyala: layanan menyala kembali (ikon senyap muncul).

## Berkas

- Dart: `app/lib/features/jeda/` (`jeda_models.dart`, `jeda_content.dart`, `jeda_controller.dart`, `jeda_bridge.dart`, `jeda_screen.dart`), uji di `app/test/jeda_test.dart`.
- Android: `app/android/app/src/main/kotlin/id/kira/kira/jeda/` (`JedaDecider`, `JedaCodec`, `JedaStore`, `JedaService`, `JedaOverlay`, `JedaPlugin`, `JedaBootReceiver`, `JedaPermissions`),
  uji di `app/android/app/src/test/kotlin/id/kira/kira/jeda/` (jalankan `./gradlew :app:testDebugUnitTest` dari `app/android`).
- Daftar aplikasi dikenal ada di tiga tempat yang harus sama: `knownSocialApps` (Dart), `JedaPlugin.KNOWN_PACKAGES`, dan `<queries>` di `AndroidManifest.xml`.
