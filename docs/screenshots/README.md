# Screenshot

Semua berkas di folder ini diambil dari build Flutter web yang sama dengan kode di repositori (390 px lebar, ukuran ponsel),
terhadap backend lokal dengan persona Raka (data dummy). Folder ini hanya menyimpan tangkapan terbaru: tiap perubahan layar
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
| `05-chat-checkin` | Chat check-in: ayam geprek tercatat sebagai komponen dengan gizi masing-masing dan total, setengah porsi, minuman terpisah |
| `06-chat-photo-kinds` | Menu foto: makanan, struk, label gizi, pindai kode batang, hasil cek |
| `07-beranda`, `07b-beranda-lengkap`, `07c-beranda-proyeksi` | Beranda (menggantikan tab 10 Tahun): langkah berikutnya dan kondisi hari ini; versi penuh dengan rencana hari ini, sinyal kebiasaan, proyeksi, rekap, target, slider, dan skenario; potongan bagian proyeksi 10 tahun |
| `08-check-followup` | Saatnya cek dengan pertanyaan "sudah dicek?" dan tombol peta ke tempat cek |
| `09-bp-protocol-intro`, `10-bp-protocol-active`, `11-bp-reading-sheet`, `12-bp-protocol-done` | Ukur tensi di rumah 7 hari (ESH 2021): panduan, hari ke-6 dengan hari pertama dibuang, catat bacaan, hasil rata-rata |
| `13-barcode`, `14-barcode-product` | Pindai kode batang; gizi nyata dari Open Food Facts dengan sumbernya |
| `15-trends` | Tren dengan penanda triase, riwayat skor risiko, dan pola tidur |
| `16-doctor-summary` | Ringkasan untuk dokter dengan tautan sementara yang bisa dicabut dan tombol PDF |
| `17-doctor-public-page` | Halaman web yang dibuka dokter lewat tautan, tanpa akun |
| `18-profile` | Profil dengan menu Rencana, pengingat, dan data dan privasi |
| `19-family` | Keluarga: undangan dan izin per jenis data |
| `20-whatsapp-link` | Kode untuk menautkan WhatsApp |
| `21-health-connect` | Langkah dan tidur dari Health Connect (di web: hanya tersedia di Android) |
| `22-privacy` | Data dan privasi: riwayat siapa membuka datamu, unduh data, ganti PIN, hapus akun |
| `23-reminders` | Pengingat lokal termasuk rencana harian, semua mati bawaan, isi tanpa angka kesehatan |
| `24-goals` | Target mingguan dengan kemajuan ditulis dengan kata |
| `25-riwayat` | Riwayat: strip 7 hari kalori dan gula, total hari ini terhadap batas, hidangan dibuka per komponen |
| `26-rencana-hari-ini` | Rencana hari ini: energi AKG 2019, usulan tiap waktu makan dengan alasan, yang sudah dimakan, olahraga, tidur |
| `27-rencana-minggu` | Rencana 7 hari: makan, olahraga atau hari istirahat, jam tidur |
| `28-preferensi-rencana` | Preferensi rencana: jam, hari dan jenis olahraga, tujuan, pengingat WhatsApp |
