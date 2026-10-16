# Arah Visual KIRA

Keputusan 2026-10-14 (diperbarui 2026-10-16). Arah: **standar kategori aplikasi kesehatan, dieksekusi penuh**, Android native feel (Material 3).
Tolok ukur kualitas: Apple Health / Google Fit (grafik tren tenang, kartu ringkasan rapi) dan Discord / Linear (dark mode yang nyaman di mata, tidak kaku, tanpa cognitive overload).
Masukan pengguna atas arah yang ditolak (kalender sobek, KMS, peta orienteering, peta rel, dacin, lembar lab, dan tampilan kaku bergaya "template AI"): hasil harus lebih
**terpercaya/klinis, hangat, tidak menakut-nakuti, dan memiliki hierarki visual yang bernapas**. Kode: `app/lib/core/theme.dart`.

## Hal yang diingat
Pita rentang risiko di atas dua kurva 10 tahun (kebiasaan sekarang vs diperbaiki) yang bergeser langsung saat slider digeser. Semua
kehangatan dan kredibilitas lain mengikuti dari sana: rentang ditampilkan jujur, selalu bersama jalur perbaikan.

## Dunia & bahasa
- **Skema Gelap Utama (Discord Dark Gray):**
  - Latar belakang utama menggunakan abu-abu gelap Discord (`#313338`), bukan hitam pekat kaku (`#121212`).
  - Kartu & kontainer permukaan menggunakan level tonal Discord (`#2B2D31` untuk kartu dasar, `#383A40` untuk kontainer terangkat).
  - Teks utama putih lembut (`#F2F3F5`) dan teks muted (`#B5BAC1`).
- **Skema Terang:** Permukaan putih dingin (`#F6F8F8`), kartu putih, tinta teal-gelap (`#14201F`).
- **Warna Primer:** Hijau-teal KIRA (`#6FD3CB` pada mode gelap, `#0B6E6A` pada mode terang) sebagai aksen segar dan identitas utama.
- **Warna Perhatian (Non-Urgent Awareness):**
  - Kuning/amber hangat Discord (`#FEE75C`, wadah `#3C3518`, teks `#FFF1A8`) untuk kurva kebiasaan sekarang, status pantau, dan pengingat kebiasaan.
  - Menggantikan warna koral/merah agar tidak alarmist dan tidak menimbulkan *cognitive overload* atau kepanikan yang tidak perlu.
  - Merah (`#E44244` / `#B3261E`) HANYA digunakan untuk kondisi darurat medis atau tanda bahaya kritis.
  - Hijau lembut (`#1F7A4A` / `#6FD3CB`) untuk jalur perbaikan/target tercapai.
- **Tipe & Tipografi:**
  - Font Figtree (variabel) / sans-serif modern pada skala tipe Material 3.
  - Bobot dinormalisasi untuk kenyamanan membaca: teks isi normal (`w400`), judul/subjudul berbobot sedang (`w600`), angka rentang besar (`w700`/`w800`). Tidak menggunakan bold tebal seragam di semua elemen.
- **Bentuk & Spacing (Anti-AI Template):**
  - Radius sudut disesuaikan agar proporsional: kartu 18 dp (diturunkan dari 24 dp bulky), input/field 14 dp (kapsul ramping), chip 10 dp, tombol berbentuk pil (`999 dp`).
  - Border kartu menggunakan garis tipis semi-transparan (`outlineVariant.withValues(alpha: 0.25)`), bukan garis kaku opaque.
  - Spacing bernapas: header memisahkan judul dan badge status di sisi berseberangan; tautan utilitas bawah dikelompokkan ke dalam satu kartu terpadu agar tidak berserakan.
- **Navigasi:** Bilah bawah Material 3 dengan 4 tujuan: **Ngobrol**, **Beranda**, **Riwayat**, dan **Cek**; Profil diakses dari avatar bilah atas. Sistem Back selalu bekerja.
- **Gerak:** Material standar, singkat; menghormati "hapus animasi" sistem. Tidak ada animasi dekoratif.

## Tidak pakai warna saja
Tingkat risiko selalu punya kata (kategori) dan bentuk: kurva sekarang garis penuh, kurva diperbaiki garis putus; luminans kedua kurva
berbeda (diuji di `test/theme_test.dart`).

## Bahasa produk
"Proyeksi risiko", "skrining", "saran gaya hidup", "masih sesuai targetmu hari ini". Tidak pernah "kamu aman" atau "kamu menderita".

## Direction contract (pengembangan saja, tidak dikirim ke app)
- THESIS: aplikasi kesehatan harian yang jujur tentang ketidakpastian; menolak angka risiko tunggal dan layar yang menakut-nakuti.
- OWN-WORLD: abu-abu gelap Discord (`#313338`) + hijau-teal + kuning hangat untuk perhatian; Figtree; kartu 18 dp; grafik pita dua kurva.
- STORY: pengguna memahami kemungkinan masa depannya sebagai rentang, melihat satu kebiasaan paling berdampak, tahu kapan cek, kembali besok.
- FIRST VIEWPORT (Beranda / 10 Tahun): kartu aksi kontekstual, ringkasan target harian yang bersih, judul kategori rentang, grafik pita dua kurva di atas lipatan.
- FORM: standar kategori (jalur pintu keluar), bukan dunia katalog; seed 495e5959.
