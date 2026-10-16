# Screenshot

Diambil 17 Oktober 2026 dari build Flutter web versi 1.1.0 (sama dengan rilis `v1.1.0`) di peramban berlayar sentuh ukuran
ponsel (390 x 844, kepadatan 2x), terhadap server `https://kira-be.byhan.id` dengan akun demo Raka (data dummy). Lokasi
peramban diatur ke sekitar ITB Bandung, jadi tempat cek terdekat adalah data peta sungguhan di sekitar titik itu. Hanya
layar yang dilihat, tidak ada data yang diubah. Tangkapan diambil lewat tengah malam, jadi catatan "hari ini" masih kosong;
riwayat, tren, dan sinyal memakai hari-hari sebelumnya.

Folder ini hanya menyimpan tangkapan terbaru: tiap perubahan layar berarti tangkapan diambil ulang dan yang lama dihapus.
Bukan tangkapan dari emulator atau ponsel Android; fitur yang butuh kamera, sensor, atau notifikasi (pindai kode batang,
Health Connect, Jeda sosmed, pengingat) hanya bisa dicoba di Android.

| Berkas | Isi |
|---|---|
| `01-login` | Masuk: kepala dengan maskot KIRA, nama pengguna atau nomor HP, PIN dengan tombol tampilkan, Lupa PIN, tautan Daftar |
| `02-register-consent` | Daftar: nama pengguna, nomor HP (alasannya di subjudul), PIN, persetujuan data dalam satu baris |
| `05-chat-checkin` | Ngobrol di awal hari: sapaan, saran kalimat, kamera, ketik, dan rekam suara |
| `07-beranda` | Beranda: kartu sapaan dengan maskot dan langkah berikutnya, lalu Hari ini (gula, natrium, lemak, gerak, tidur) |
| `07b-beranda-lengkap` | Beranda lanjutan: rencana hari ini dan sinyal kebiasaan 7 hari |
| `07c-beranda-proyeksi` | Sinyal kebiasaan dengan tingkat ditulis, lalu Kira-kira 10 tahun: rentang risiko diabetes |
| `08-check-followup` | Saatnya cek: kartu dengan maskot, alasan, persiapan, dan Masukkan hasil; tempat cek terdekat di bawahnya |
| `08b-tempat-cek-terdekat` | Daftar puskesmas, klinik, dan rumah sakit di sekitar dengan jarak dan tombol rute |
| `15-trends` | Tren dan penanda: penanda triase, tren hasil cek, dan kebiasaan harian dengan garis batas |
| `16-doctor-summary` | Ringkasan untuk dokter (30 hari) siap dibagikan sebagai PDF atau tautan |
| `18-profile` | Profil dengan menu dikelompokkan: Kesehatanmu, Terhubung, Pengaturan |
| `19-family` | Keluarga: apa yang dibagikan, undangan, dan izin per jenis data |
| `22-privacy` | Data dan privasi: persetujuan, siapa yang membuka datamu, unduh data, ganti PIN, hapus akun |
| `23-reminders` | Pengingat lokal, semua mati bawaan, isi tanpa data kesehatan |
| `24-goals` | Target mingguan kosong dengan maskot dan tombol Tambah target |
| `25-riwayat` | Riwayat: strip 7 hari kalori dan gula, lalu per hari |
| `26-rencana-hari-ini` | Rencana hari ini: energi, usulan tiap waktu makan dengan gizi dan alasannya |
| `29-rekam-medis` | Rekam medis kosong dengan maskot dan ajakan bercerita di Ngobrol |

Tiga tangkapan lama dipertahankan karena dipakai pitch deck dan belum diambil ulang (tampilan sebelum versi 1.1.0):
`06-chat-photo-kinds` (menu foto), `10-bp-protocol-active` (tensi di rumah 7 hari), `13-barcode` (pindai kode batang).
