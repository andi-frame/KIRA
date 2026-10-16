# Screenshot

Semua berkas di folder ini diambil dari build Flutter web yang sama dengan kode di repositori (390 px lebar, ukuran ponsel),
terhadap backend lokal dengan persona Raka (alur utama) dan Sari (hipertensi terkontrol; untuk rekam medis, tren detak jantung, dan ringkasan
dokter), keduanya data dummy dari `seed.raka` dan `seed.demo_users`. Tangkapan diambil dengan peramban berlayar sentuh ukuran ponsel (390 x 844). Folder ini hanya menyimpan tangkapan terbaru: tiap perubahan layar
berarti tangkapan diambil ulang dan yang lama dihapus. Bukan tangkapan dari emulator atau ponsel Android; layar yang butuh kamera,
sensor, atau notifikasi hanya bisa dicoba di Android (di web, pindai kode batang memakai ketik nomor, dan notifikasi tidak tersedia).

Model bahasa pada `05-chat-checkin` adalah model sungguhan lewat gerbang 9router. Persentase risiko adalah perkiraan, bukan hasil klinis
(insidensi per kategori FINDRISC bersumber sekunder, interpolasi antar kategori adalah asumsi tim; lihat `docs/sumber-angka-klinis.md`).

| Berkas | Isi |
|---|---|
| `01-login` | Masuk dengan nama pengguna atau nomor HP, tautan Lupa PIN |
| `02-register-consent` | Daftar dengan persetujuan data kesehatan (kotak centang, teks yang bisa dibaca) |
| `03-reset-pin` | Lupa PIN: kode lewat WhatsApp yang tertaut |
| `04-consent-gate` | Persetujuan ulang untuk akun lama, tidak bisa dilewati |
| `05-chat-checkin` | Obrolan yang dipulihkan dari server: ayam geprek tercatat sebagai komponen dengan gizi masing-masing dan total, label waktu makan (Makan siang) yang bisa diubah, tombol "Setengah porsi" dan "Hapus catatan ini" |
| `05b-chat-setengah-porsi` | Setelah "Setengah porsi" diketuk: porsi menjadi setengah dan tombol berubah menjadi "Porsi biasa" (saklar, tidak menurun berulang) |
| `05c-chat-waktu-makan` | "Nasi dengan ayam katsu" jam 15.40 tidak diam-diam menjadi selingan: KIRA bertanya waktu makannya dengan pilihan satu ketukan |
| `05d-chat-riwayat-obrolan` | Tombol riwayat di kiri atas: riwayat obrolan hari ini (satu per hari, dibersihkan saat hari berganti) dan tombol hapus |
| `06-chat-photo-kinds` | Menu foto: makanan, struk, label gizi, pindai kode batang, hasil cek |
| `07-beranda`, `07b-beranda-lengkap`, `07c-beranda-proyeksi` | Beranda (menggantikan tab 10 Tahun): langkah berikutnya dan kondisi hari ini; versi penuh dengan rencana hari ini, sinyal kebiasaan, proyeksi, rekap, target, slider, dan skenario; potongan bagian proyeksi 10 tahun beserta kartu "Dasar angka ini" (dari catatan, dari profil, atau belum diketahui) |
| `08-check-followup` | Saatnya cek; di bawahnya tempat cek terdekat dari data peta |
| `08b-tempat-cek-terdekat` | Tempat cek terdekat dari OpenStreetMap (puskesmas, klinik, rumah sakit umum), tombol rute Google Maps per tempat, keterangan sumber, dan "Cari puskesmas lain di Google Maps" |
| `08c-catat-detak-jantung` | Isian detak jantung istirahat dengan cara menghitungnya |
| `08d-tensi-dengan-nadi` | Isian tensi dengan nadi (boleh dikosongkan) |
| `08e-detak-jantung-tersimpan` | Hasil detak jantung dalam kata tenang, tanpa klaim proyeksi berubah |
| `09-bp-protocol-intro`, `10-bp-protocol-active`, `11-bp-reading-sheet`, `12-bp-protocol-done` | Ukur tensi di rumah 7 hari (ESH 2021): panduan, hari ke-6 dengan hari pertama dibuang, catat bacaan, hasil rata-rata |
| `13-barcode`, `14-barcode-product` | Pindai kode batang; gizi nyata dari Open Food Facts dengan sumbernya |
| `15-trends` | Tren dengan penanda triase, riwayat skor risiko, dan pola tidur |
| `15b-trends-detak-jantung` | Grafik detak jantung istirahat dengan batas normal 60 dan 100, dan gula darah puasa (Sari) |
| `16-doctor-summary` | Ringkasan untuk dokter dengan tautan sementara yang bisa dicabut dan tombol PDF |
| `17-doctor-public-page` | Halaman web yang dibuka dokter lewat tautan, tanpa akun |
| `18-profile` | Profil (Sari) dengan menu Rekam medis, Rencana, pengingat, Jeda sosmed, dan data dan privasi |
| `19-family` | Keluarga: undangan dan izin per jenis data |
| `20-whatsapp-link` | Kode untuk menautkan WhatsApp |
| `21-health-connect` | Langkah dan tidur dari Health Connect (di web: hanya tersedia di Android) |
| `22-privacy` | Data dan privasi: riwayat siapa membuka datamu, unduh data, ganti PIN, hapus akun |
| `23-reminders` | Pengingat lokal termasuk rencana harian, semua mati bawaan, isi tanpa angka kesehatan |
| `24-goals` | Target mingguan dengan kemajuan ditulis dengan kata |
| `25-riwayat` | Riwayat: strip 7 hari kalori dan gula, total hari ini terhadap batas, hidangan dibuka per komponen |
| `25b-riwayat-tidur-ubah-hapus` | Satu hari dengan makan, minum, dan bagian Tidur (juga Olahraga bila ada) yang masing-masing bisa diubah atau dihapus |
| `25c-riwayat-makan-dibuka` | Catatan makan dibuka: komponen, ubah gram, dan "Hapus catatan ini" |
| `26-rencana-hari-ini` | Rencana hari ini: energi AKG 2019, usulan tiap waktu makan dengan alasan, yang sudah dimakan, olahraga, tidur |
| `27-rencana-minggu` | Rencana 7 hari: makan, olahraga atau hari istirahat, jam tidur |
| `28-preferensi-rencana` | Preferensi rencana: jam, hari dan jenis olahraga, tujuan, pengingat WhatsApp |
| `29-rekam-medis`, `29b-rekam-medis-formulir` | Rekam medis (Sari): daftar per jenis dengan nilai hasil lab, saringan jenis, catatan bahwa KIRA hanya menyimpan, dan formulir tambah |

Tidak ada tangkapan untuk Jeda sosmed dan sebagian lembar bawah (mis. riwayat obrolan di perangkat dengan bilah navigasi sistem): fiturnya khusus Android dan web tidak menampilkannya;
ruang di atas bilah Home/Back diuji dengan uji widget (`heart_rate_and_maps_test.dart`), bukan tangkapan.
