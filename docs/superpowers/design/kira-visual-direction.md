# Arah Visual KIRA

Keputusan 2026-10-14. Arah: **standar kategori aplikasi kesehatan, dieksekusi penuh**, Android native feel (Material 3).
Tolok ukur kualitas: Apple Health / Google Fit (grafik tren tenang, kartu ringkasan rapi) dan Flo / Headspace (hangat, ramah).
Masukan pengguna atas arah yang ditolak (kalender sobek, KMS, peta orienteering, peta rel, dacin, lembar lab): hasil harus lebih
**terpercaya/klinis, hangat, dan tetap punya satu hal yang diingat**. Kode: `app/lib/core/theme.dart`.

## Hal yang diingat
Pita rentang risiko di atas dua kurva 10 tahun (kebiasaan sekarang vs diperbaiki) yang bergeser langsung saat slider digeser. Semua
kehangatan dan kredibilitas lain mengikuti dari sana: rentang ditampilkan jujur, selalu bersama jalur perbaikan.

## Dunia & bahasa
- Permukaan putih dingin (`#F6F8F8`), kartu putih, tinta teal-gelap (`#14201F`). Tanpa krem, tanpa kuningan, tanpa ungu AI.
- Satu primer: hijau-teal tua `#0B6E6A`. Satu warna hangat khusus "perlu perhatian" (koral `#B8492A`, wadah `#FFE3D8`) untuk kurva
  kebiasaan sekarang dan kartu "Saatnya cek". Hijau lembut `#1F7A4A` untuk jalur perbaikan. Merah (`#B3261E`) hanya untuk darurat.
- Gelap adalah skema kelas satu, bukan inversi (lihat `kiraDarkTheme`).
- Tipe: Figtree (variabel) pada skala tipe Material 3; kontras lewat bobot, bukan font kedua. Angka rentang besar berbobot 800.
- Bentuk (dikunci): kartu 24 dp, input 16 dp, chip 12 dp, tombol pil. Elevasi lewat permukaan tonal dan garis tipis, bukan bayangan.
- Navigasi: bilah bawah Material 3 dengan 3 tujuan (Ngobrol, 10 Tahun, Cek); Profil dari bilah atas. Sistem Back selalu bekerja.
- Gerak: Material standar, singkat; menghormati "hapus animasi" sistem. Tidak ada animasi dekoratif.

## Tidak pakai warna saja
Tingkat risiko selalu punya kata (kategori) dan bentuk: kurva sekarang garis penuh, kurva diperbaiki garis putus; luminans kedua kurva
berbeda (diuji di `test/theme_test.dart`).

## Bahasa produk
"Proyeksi risiko", "skrining", "saran gaya hidup", "masih sesuai targetmu hari ini". Tidak pernah "kamu aman" atau "kamu menderita".

## Direction contract (pengembangan saja, tidak dikirim ke app)
- THESIS: aplikasi kesehatan harian yang jujur tentang ketidakpastian; menolak angka risiko tunggal dan layar yang menakut-nakuti.
- OWN-WORLD: putih dingin + hijau-teal tua + koral hanya untuk perhatian; Figtree; kartu 24 dp; grafik pita dua kurva.
- STORY: pengguna memahami kemungkinan masa depannya sebagai rentang, melihat satu kebiasaan paling berdampak, tahu kapan cek, kembali besok.
- FIRST VIEWPORT (10 Tahun): judul kategori rentang, grafik pita dua kurva di atas lipatan, satu kartu kebiasaan paling berdampak.
- FORM: standar kategori (jalur pintu keluar), bukan dunia katalog; seed 495e5959.
