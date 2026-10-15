# Privasi dan keamanan akun

Dokumen ini mencatat apa yang KIRA lakukan terhadap data kesehatan penggunanya, supaya klaim di aplikasi, proposal, dan kode
tetap sama. Bila praktiknya berubah, ubah teksnya bersamaan dengan `CONSENT_VERSION`
([`backend/app/services/account.py`](../backend/app/services/account.py)): akun yang menyetujui versi lama diminta menyetujui ulang.

## Dasar hukum yang dirujuk

UU No. 27 Tahun 2022 tentang Pelindungan Data Pribadi (UU PDP) menggolongkan informasi kesehatan sebagai data pribadi yang
spesifik. KIRA meminta persetujuan eksplisit sebelum memproses dan menyediakan hak pemilik data untuk mengakses salinan dan
menghapus data. Dokumen ini bukan nasihat hukum; peninjauan oleh konsultan hukum diperlukan sebelum peluncuran ke pengguna umum.

## Persetujuan

- Pendaftaran ditolak server (HTTP 422) bila `consent` bukan `true`; aplikasi menampilkan kotak centang dan teks yang bisa dibaca.
- Waktu dan versi persetujuan disimpan di `users.consented_at` dan `users.consent_version`.
- Akun yang dibuat sebelum ada persetujuan, atau yang versinya sudah lama, dihadang dialog persetujuan yang tidak bisa dilewati.
  Pilihannya hanya "Saya setuju" atau "Keluar".

## Hak pemilik data

| Hak | Cara |
|---|---|
| Mengakses salinan | `GET /account/export`: satu JSON berisi profil, catatan beserta itemnya, hasil cek, snapshot risiko, percakapan, undangan keluarga. Tanpa PIN. |
| Menghapus | `POST /account/delete` dengan PIN. Semua tabel anak ikut terhapus (`ON DELETE CASCADE`); undangan keluarga yang menunggu nomornya juga dihapus. Nomor HP dan nama pengguna bisa dipakai lagi. |
| Mengetahui siapa yang melihat | `GET /account/access-log`: anggota keluarga yang membuka status dan penerima tautan dokter. Akses beruntun dalam 30 menit dilipat jadi satu catatan. |
| Menarik persetujuan | Menghapus akun. |

## Ke mana data pergi (jujur)

- **Server KIRA (PostgreSQL):** seluruh data pengguna. Aplikasi hanya menyimpan token login di penyimpanan aman perangkat.
- **Penyedia model bahasa (Anthropic):** teks dan foto percakapan, agar bisa dibaca menjadi catatan. Angka risiko, gizi, dan target dihitung
  oleh kode KIRA, bukan oleh model.
- **Layanan transkripsi suara (Groq, Whisper):** rekaman suara yang dikirim pengguna.
- **WhatsApp:** hanya bila pengguna menautkan nomornya; pesan melewati jembatan Baileys yang tidak resmi (prototype).

## Sesi dan PIN

- Token akses berlaku 60 menit; perangkat memperbaruinya dengan token penyegar (30 hari, berputar tiap dipakai, hanya hash SHA-256 yang disimpan).
  Pengguna tidak terlempar keluar tiap beberapa jam, tetapi token yang bocor tidak berlaku selamanya.
- Keluar mengakhiri sesi di server. Ganti PIN atau atur ulang PIN mengakhiri semua sesi lain.
- PIN disimpan sebagai hash Argon2. Percobaan masuk yang salah dibatasi per akun (5 kali, 15 menit), termasuk saat berganti antara nama pengguna dan nomor.
- **Lupa PIN:** kode 6 angka dikirim ke WhatsApp yang sudah tertaut. Berlaku 10 menit, hanya hash (HMAC dengan kunci server) yang disimpan,
  5 salah mengunci kode itu, permintaan dibatasi 3 per jam, jarak kirim ulang 60 detik. Jawaban permintaan sama untuk akun yang ada maupun tidak,
  agar tidak bisa dipakai menebak siapa yang terdaftar. Teks kode dihapus dari antrean pesan setelah terkirim.
  **Batasnya:** tanpa WhatsApp tertaut, KIRA tidak punya cara membuktikan pemilik akun, dan layar Lupa PIN mengatakannya terang-terangan.

## Tautan untuk dokter

- Token acak 48 byte; yang disimpan hanya hash-nya, jadi tautan hanya terlihat sekali saat dibuat.
- Berlaku 1 sampai 30 hari, maksimal 5 tautan aktif, bisa dicabut kapan saja. Tautan salah, kedaluwarsa, dan dicabut dijawab sama (404) agar tidak bisa dibedakan.
- Halaman publik tanpa skrip dan tanpa sumber luar, dengan `Cache-Control: no-store`, `X-Robots-Tag: noindex`, dan `Referrer-Policy: no-referrer`.
  Tidak memuat nomor HP.
- Setiap pembukaan dihitung dan tercatat di riwayat akses pemilik.

## Yang belum

- Peninjauan hukum atas teks persetujuan dan kebijakan retensi.
- Rate limit per IP di tingkat jaringan (lihat `docs/deploy.md` untuk rekomendasi di depan API).
- Enkripsi kolom di basis data (saat ini mengandalkan enkripsi disk penyedia hosting).
- Penetration test oleh pihak ketiga.
