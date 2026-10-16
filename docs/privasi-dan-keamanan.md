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
- **Penyedia model bahasa** (Anthropic, atau gerbang yang dipilih lewat `LLM_BASE_URL` seperti 9router, yang meneruskan ke model di belakangnya): teks dan foto percakapan, agar bisa dibaca menjadi catatan. Gerbang pihak ketiga berarti satu pihak lagi yang menerima isi percakapan; pilih yang kebijakan datanya kamu percayai. Angka risiko, gizi, dan target dihitung
  oleh kode KIRA, bukan oleh model.
- **Layanan transkripsi suara (Groq, Whisper):** rekaman suara yang dikirim pengguna.
- **WhatsApp:** hanya bila pengguna menautkan nomornya; pesan melewati jembatan Baileys yang tidak resmi (prototype).

## Rencana dan pengingat

- **Data baru:** preferensi rencana (`plan_preferences`: jam bangun/makan/olahraga, hari olahraga, tujuan, kanal pengingat, jam tenang)
  dan penggantian usulan (`plan_overrides`). Keduanya ikut `GET /account/export` dan terhapus bersama akun.
- **Rencana dihitung kode KIRA** dari profil, catatan, dan katalog hidangan; model bahasa hanya menyampaikannya lewat tool baca-saja.
- **Pengingat WhatsApp rencana** mati secara bawaan, hanya untuk nomor yang tertaut, maksimal 4 pesan WhatsApp per hari (semua jenis),
  tidak di jam tenang, dan bisa dimatikan dengan membalas "stop pengingat". Isinya boleh memuat nama usulan makan dan perkiraan
  energi, **tidak pernah** hasil pemeriksaan (tensi, gula darah).
- **Notifikasi lokal** rencana juga mati secara bawaan dan isinya generik ("Waktunya makan siang"), tanpa angka kesehatan,
  karena layar kunci bisa dilihat orang lain.
- **Katalog makanan** (sekitar 1.400 token daftar nama) ikut terkirim ke penyedia model bahasa bersama pesan pengguna supaya
  makanan bisa dipetakan; katalog itu bukan data pribadi.

## Obrolan dan rekam medis

- **Obrolan disimpan satu hari.** Agar obrolan tidak hilang saat aplikasi ditutup, pesan hari ini disimpan di server dan dipulihkan
  saat aplikasi dibuka lagi. Saat hari berganti (WIB), obrolan hari sebelumnya dihapus otomatis (tengah malam, dan juga saat
  riwayat diminta). Pengguna juga bisa menghapus obrolan hari ini sendiri dari tombol riwayat. Catatan makan, tidur, dan
  olahraga yang sudah tersimpan tidak ikut terhapus. Pesan disimpan apa adanya (termasuk yang diketik pengguna) bersama id
  catatan; angka di kartu "Yang kucatat" diambil ulang dari catatannya, jadi selalu terkini.
- **Rekam medis** (diagnosis, hasil lab, obat yang dipakai, alergi, dst.) ditulis sendiri oleh pengguna, di formulir atau lewat
  cerita di Ngobrol. KIRA hanya menyimpan dan menggolongkan; tidak menilai isinya, tidak mendiagnosis, tidak menyarankan obat.
  Rekam medis ikut di unduhan data dan terhapus bersama akun.
- **Ringkasan untuk dokter** (dan tautan/PDF-nya) memuat rekam medis yang tercatat (15 terbaru), berlabel "ditulis sendiri oleh
  pasien, tidak diverifikasi KIRA". Pengguna yang tidak ingin membagikannya cukup tidak memasukkan rekam medis, atau
  menghapusnya sebelum membagikan tautan.
- **Fasilitas kesehatan terdekat**: koordinat pengguna dikirim ke server KIRA, lalu (tanpa identitas pengguna) ke OpenStreetMap
  Overpass atau, bila kunci diisi, Google Places untuk mencari tempat terdekat. Hasilnya disimpan sementara di memori server
  per sel sekitar 1 km (6 jam), bukan per pengguna.

## Jeda sosmed (Android, opsional)

- Mati secara bawaan. Setelah dinyalakan butuh dua izin yang diberikan sendiri oleh pengguna di pengaturan Android: **akses penggunaan**
  (agar tahu aplikasi mana yang di depan) dan **tampil di atas aplikasi lain** (agar kartu bisa muncul).
- KIRA hanya membaca **nama paket** aplikasi yang sedang di depan, tidak membaca isi layar, dan tidak mengirimnya ke server. Hanya
  aplikasi yang dicentang pengguna yang ditahan; WhatsApp tidak ada di daftar.
- Isi kartu (usulan makan, olahraga, jam tidur, status "belum tercatat") disimpan di penyimpanan pribadi aplikasi di ponsel, bukan di
  server, dan terhapus saat Jeda dimatikan atau pengguna keluar akun. Berbeda dari notifikasi, kartu memuat nama usulan makan dan
  olahraga karena tampil saat pengguna sedang memegang ponsel; tidak pernah memuat hasil pemeriksaan (tensi, gula darah).
- Pengguna bisa melewati kartu sampai besok, dan satu jenis kartu tampil paling banyak tiga kali sehari.

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
