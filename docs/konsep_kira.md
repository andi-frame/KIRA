# KIRA — Konsep Hackathon JOINTS 2026 (Healthcare Subtema 5)

Oct 14, 2026 · @Andi Farhan

## Ringkasan &amp; positioning

**KIRA** adalah teman ngobrol 1 menit sehari yang memproyeksikan risiko diabetes dan hipertensi penggunanya 10 tahun ke depan, menunjukkan kebiasaan mana yang paling berdampak, dan tahu kapan pengguna harus memeriksakan diri, lalu belajar dari hasil pemeriksaan itu.

**Arti nama:** KIRA = *Knowledge-driven Insight for Risk Awareness*, sekaligus dari kata "kira-kira" (memperkirakan), sesuai fungsi utamanya memproyeksikan kesehatan. Tagline: *"Kira-kira kesehatanmu 10 tahun lagi seperti apa? Tanya KIRA."*

**Pitch satu kalimat:** *Hampir semua anak muda dengan diabetes tidak tahu dirinya sakit. KIRA menunjukkan masa depan kesehatanmu hari ini, dan memberi tahu kapan kamu harus cek.*

Tiga pembeda utama (jawaban untuk "apa bedanya dengan aplikasi diet atau ChatGPT?"):

1. **Kira-kira 10 Tahun (what-if):** dua proyeksi berdampingan, kebiasaan sekarang vs kebiasaan yang diperbaiki, dengan slider yang langsung menggeser grafik.
2. **Tahu kapan harus cek (uncertainty-aware):** model menyimpan tingkat ketidakpastian. Saat terlalu tinggi atau pola mengarah ke zona berisiko, KIRA meminta pengukuran yang paling berguna (CKG, Posyandu, cek gula darah) dan mengkalibrasi ulang setelah hasilnya masuk.
3. **Berganti mode setelah diagnosis:** dari pencegahan ke pengelolaan. Fokus beralih ke pola makan yang paling menaikkan gula darah, kepatuhan obat, jadwal kontrol, dan ringkasan 30 hari untuk dokter.

Prinsip produk: KIRA **bukan alat diagnosis**. KIRA memproyeksikan risiko berbasis skor tervalidasi dan mendorong orang ke pemeriksaan nyata; keputusan klinis tetap di tenaga medis.

## Masalah &amp; data pendukung

Usia produktif dengan risiko diabetes dan hipertensi tidak merasa sakit, jadi tidak cek, dan baru ketahuan saat sudah komplikasi. Data yang bisa dipakai di pitch:


| Fakta                                                                            | Angka                                                       | Sumber                                                                                                                                                     |
| -------------------------------------------------------------------------------- | ----------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Diabetes dari pemeriksaan gula darah (usia &gt;15 th, SKI 2023)                  | 11,7% (sekitar 30 juta orang), baru 10–15 juta terdiagnosis | [MerahPutih](https://www.merahputih.com/post/read/diabetes-kini-serang-usia-muda-gaya-hidup-jadi-pemicu-utama)                                             |
| Diabetes tidak terdiagnosis pada usia 15–29 tahun                                | 98,4%                                                       | [Alomedika](https://alomedika.com/diabetes-yang-luput-dari-diagnosis-di-indonesia-telaah-jurnal-alomedika)                                                 |
| Tingkat diagnosis hipertensi (2023)                                              | 26,9%                                                       | [BMJ Open via BIDMC](https://research.bidmc.org/oscar/publications/hypertension-care-performance-indonesia-evidence-three-waves-nationally-representative) |
| Temuan CKG 2026 (52 juta dewasa diperiksa tensinya)                              | 4,9 juta hipertensi, 5,5 juta prehipertensi                 | [CNA](https://www.cna.id/indonesia/cek-kesehatan-gratis-hipertensi-obesitas-diabetes-kemenkes-49506)                                                       |
| Temuan CKG 2026 gula darah                                                       | 992 ribu diabetes, 1,9 juta prediabetes                     | [CNA](https://www.cna.id/indonesia/cek-kesehatan-gratis-hipertensi-obesitas-diabetes-kemenkes-49506)                                                       |
| Obesitas sentral usia ≥15 tahun                                                  | 30,8% (2018) naik ke 36,8% (2023)                           | [KEMAS UNNES](https://journal.unnes.ac.id/journals/kemas/article/download/32829/9083/153788)                                                               |
| Alasan berhenti minum obat hipertensi (SKI 2023)                                 | 64,9% merasa sehat, 18,1% bosan/malas                       | [Repository BKU](https://repository.bku.ac.id/id/eprint/3687/7/Bab%201.pdf)                                                                                |
| Biaya BPJS untuk gagal ginjal (2025), komplikasi hilir hipertensi &amp; diabetes | Rp13,3 triliun                                              | [NU Online](https://nu.or.id/kesehatan/banyak-anak-muda-cuci-darah-dokter-jelaskan-pemicu-dan-cara-menjaga-kesehatan-ginjal-jq4fP)                         |


**Narasi pembuka pitch:** penyakitnya diam, orangnya merasa sehat, dan sistem baru bertemu mereka saat sudah terlambat. Celah yang diisi KIRA ada di antara "merasa sehat" dan "diperiksa".

## Persona &amp; user flow

Pengguna utama adalah orang usia 20–40 tahun yang merasa sehat dan belum rutin cek, misalnya Raka di bagian Skenario demo. Alurnya berupa siklus: check-in harian memperbarui proyeksi, dan proyeksi yang belum yakin memicu pemeriksaan nyata.

[embed: node/7ddb570f-51ee]

Selama proyeksi cukup yakin, pengguna hanya melihat what-if dan lanjut check-in; saat rentangnya lebar atau risiko naik, KIRA meminta cek, lalu hasilnya mengkalibrasi ulang atau memindahkan pengguna ke mode pengelolaan.

## Fitur MVP

MVP difokuskan pada satu alur yang jalan penuh dari onboarding sampai kalibrasi ulang. Fitur yang tidak masuk demo ditaruh di roadmap.


| Fitur                               | Prioritas                | Isi                                                                                                                                                                                                                                                                                                                                                              | Bobot penilaian yang didukung |
| ----------------------------------- | ------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| Onboarding percakapan               | Wajib                    | 6–8 pertanyaan via chat/voice: usia, jenis kelamin, tinggi/berat, lingkar perut (opsional), riwayat keluarga, aktivitas, merokok                                                                                                                                                                                                                                 | Fungsionalitas &amp; Desain   |
| Check-in multimodal                 | Wajib                    | Tiga modal input: **suara** (STT), **teks**, dan **foto** (makanan atau struk belanja). AI mengekstrak makanan, minuman manis, jam tidur, aktivitas                                                                                                                                                                                                              | Implementasi Teknis           |
| Baca struk belanja                  | Wajib                    | Foto struk minimarket/restoran → daftar item → estimasi gula, garam, kalori dari tabel gizi                                                                                                                                                                                                                                                                      | Inovasi                       |
| Database makanan lokal              | Wajib                    | Pemetaan ke Tabel Komposisi Pangan Indonesia + porsi khas (nasi padang, gorengan, es teh, kopi susu gula aren)                                                                                                                                                                                                                                                   | Inovasi, Implementasi         |
| Proyeksi risiko 10 tahun            | Wajib                    | Skor risiko diabetes &amp; hipertensi + rentang ketidakpastian, dihitung oleh kalkulator skor yang dipanggil LLM sebagai tool                                                                                                                                                                                                                                    | Implementasi Teknis           |
| Kira-kira 10 Tahun (what-if)        | Wajib                    | Dua kurva berdampingan + slider kebiasaan; menyorot satu kebiasaan paling berdampak                                                                                                                                                                                                                                                                              | Inovasi, Desain               |
| Rekomendasi makanan &amp; aktivitas | Wajib                    | **Satu arah:** saran proaktif dari pola pengguna ("minggu ini gulamu tinggi dari minuman, coba ganti es teh jadi tawar"). **Diskusi:** pengguna bertanya, misalnya "mau makan rendang malam ini, boleh berapa?", lalu AI menghitung porsi yang masih sesuai sisa target harian dan menyarankan kompensasi (porsi nasi lebih kecil, jalan 20 menit setelah makan) | Inovasi, Fungsionalitas       |
| Rekomendasi cek                     | Wajib                    | Muncul saat ketidakpastian tinggi atau risiko naik; menyebut jenis cek dan lokasi CKG/Posyandu                                                                                                                                                                                                                                                                   | Dampak &amp; Kelayakan        |
| Input hasil pemeriksaan             | Wajib                    | Foto hasil CKG/lab atau layar tensimeter → baca angka → kalibrasi ulang proyeksi                                                                                                                                                                                                                                                                                 | Implementasi Teknis           |
| Mode setelah diagnosis              | Wajib (versi sederhana)  | Fokus saran berubah ke pengelolaan, pengingat obat &amp; kontrol                                                                                                                                                                                                                                                                                                 | Dampak                        |
| Check-in via WhatsApp               | Nice-to-have (prototype) | Check-in tanpa install aplikasi. Untuk prototype memakai Baileys atau library WhatsApp tidak resmi lainnya; untuk produksi wajib pindah ke WhatsApp Business Platform resmi (lihat catatan di bawah)                                                                                                                                                             | Kelayakan                     |
| Terhubung dengan keluarga           | Nice-to-have             | Pengguna mengundang anggota keluarga dengan persetujuan; keluarga melihat ringkasan yang dipilih pengguna (misalnya status check-in dan pengingat kontrol, bukan detail makanan). Bisa juga mengirim undangan skrining ke keluarga karena riwayat keluarga meningkatkan risiko                                                                                   | Dampak                        |
| Ringkasan untuk dokter              | Nice-to-have             | Halaman 1 lembar: pola makan, tidur, tensi/gula 30 hari                                                                                                                                                                                                                                                                                                          | Dampak                        |
| Korelasi makanan vs gula darah      | Nice-to-have             | Untuk pengguna yang punya glukometer: makanan mana yang paling menaikkan gula                                                                                                                                                                                                                                                                                    | Inovasi                       |
| Integrasi SATUSEHAT                 | Roadmap                  | Tarik hasil CKG otomatis dengan persetujuan pengguna                                                                                                                                                                                                                                                                                                             | Kelayakan                     |


**Catatan WhatsApp:** Baileys dan library sejenis bekerja dengan meniru WhatsApp Web, bukan API resmi. Risikonya: nomor bisa diblokir (termasuk saat demo), melanggar ketentuan layanan WhatsApp, dan lemah untuk data kesehatan. Untuk demo pakai nomor cadangan dan siapkan alur yang sama di aplikasi sebagai fallback; di pitch sebutkan bahwa produksi memakai WhatsApp Business Platform resmi.

**Batas yang disengaja:** tidak ada saran obat atau dosis, tidak ada klaim diagnosis, dan tidak menggantikan konsultasi.

## Arsitektur sistem &amp; tech stack

Arsitekturnya tiga lapisan: aplikasi mobile Flutter, backend Python yang memisahkan pekerjaan AI dari perhitungan risiko, serta data dan layanan eksternal.

[embed: node/144e5456-0714]

Percakapan dan rekomendasi dikerjakan LLM, sedangkan angka risiko dan gizi berasal dari tool deterministik di Python, sehingga setiap angka yang ditampilkan bisa dilacak ke skor dan inputnya.


| Lapisan                | Pilihan                                                                              | Alasan                                                                               |
| ---------------------- | ------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------ |
| Mobile app             | Flutter (Android sebagai target utama, APK untuk juri)                               | Satu codebase, akses kamera dan mikrofon native                                      |
| Kanal chat             | Chat di aplikasi + WhatsApp via Baileys (prototype)                                  | Check-in tanpa membuka aplikasi; produksi pindah ke WhatsApp Business Platform resmi |
| Backend                | Python FastAPI                                                                       | Satu bahasa dengan orkestrasi LLM dan tool kalkulator                                |
| Database               | PostgreSQL di server (SQLAlchemy + Alembic)                                          | Profil, state, ringkasan, log, dan percakapan tersimpan terpusat                     |
| LLM                    | LLM dengan tool calling dan input gambar, diorkestrasi LangGraph                     | Ekstraksi, rekomendasi, dan diskusi makanan                                          |
| Input suara &amp; foto | Speech-to-text API di backend; model vision untuk foto makanan, struk, dan hasil cek | Tiga modal input: suara, teks, foto                                                  |
| Tool kalkulator        | Fungsi Python biasa                                                                  | FINDRISC, kategori tensi, gizi, sisa target, what-if                                 |
| Bot WhatsApp           | Service Node.js terpisah (Baileys adalah library JavaScript)                         | Hanya meneruskan pesan ke FastAPI                                                    |


Detail implementasi ada di tab Plan implementasi.

Pilihan ini bisa diganti sesuai keahlian tim; yang penting pemisahan antara ekstraksi AI dan perhitungan risiko tetap dijaga.

## Model: LLM wrapper + context management + tool kalkulator

Intinya adalah LLM wrapper dengan context management yang kuat, ditambah dua sampai empat **tool kecil yang deterministik** untuk angka (skor risiko, gizi, sisa target harian). LLM yang memutuskan kapan memanggil tool; tool yang menghitung angkanya.

Kenapa tetap perlu tool walau mainnya LLM: LLM bisa memberi angka risiko atau kalori yang berbeda setiap ditanya, dan juri hampir pasti bertanya "ini cuma wrapper ChatGPT?". Dengan tool calling, jawabannya: percakapan oleh LLM, angka oleh fungsi yang bisa diaudit. Kalkulator FINDRISC hanya tabel poin, jadi biaya pengerjaannya kecil.

### Lapisan konteks


| Lapisan                     | Isi                                                                                                   | Diperbarui                                 | Masuk ke prompt                              |
| --------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------ | -------------------------------------------- |
| System prompt               | Peran, batas klinis, gaya bahasa, daftar tool                                                         | Tetap                                      | Selalu                                       |
| Profil kesehatan            | Usia, jenis kelamin, IMT, lingkar perut, riwayat keluarga, merokok, preferensi makanan                | Onboarding + saat pengguna mengoreksi      | Selalu, ringkas                              |
| State kesehatan terstruktur | Skor risiko terakhir + rentangnya, hasil cek, diagnosis, mode (pencegahan/pengelolaan), target harian | Setiap ada hasil cek atau perhitungan baru | Selalu, sebagai JSON                         |
| Ringkasan berjalan          | Pola mingguan: rata-rata minuman manis, tidur, aktivitas, kebiasaan yang sedang dilatih               | Dirangkum otomatis tiap minggu             | Selalu                                       |
| Log terbaru                 | Detail makanan, tidur, aktivitas 24–72 jam terakhir                                                   | Setiap check-in                            | Selalu                                       |
| Log lama                    | Riwayat detail lebih dari 3 hari                                                                      | Disimpan di database                       | Hanya bila relevan (diambil lewat pencarian) |
| Percakapan aktif            | Beberapa giliran terakhir                                                                             | Setiap pesan                               | Selalu                                       |


Prinsipnya: yang sering dibutuhkan disimpan ringkas dan selalu ada, detail lama diambil hanya saat ditanya. Ini menjaga biaya token dan membuat jawaban tetap konsisten.

### Tool yang bisa dipanggil LLM


| Tool                         | Fungsi                                                                             | Sumber angka                                                                          |
| ---------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| `cari_gizi(makanan, porsi)`  | Gula, garam, lemak, kalori per porsi                                               | Tabel Komposisi Pangan Indonesia                                                      |
| `sisa_target_harian()`       | Sisa batas gula, garam, lemak hari ini dari log                                    | Batas konsumsi gula, garam, lemak harian Kemenkes (verifikasi angka dari regulasinya) |
| `hitung_risiko()`            | Skor FINDRISC (diabetes, 10 tahun) dan Framingham Hypertension (4 tahun) + rentang | Skor tervalidasi, dari profil + state                                                 |
| `simulasi_whatif(perubahan)` | Hitung ulang risiko dengan kebiasaan yang digeser                                  | Sama dengan `hitung_risiko`                                                           |
| `cari_faskes(lokasi)`        | Posyandu/Puskesmas/CKG terdekat                                                    | Data lokasi faskes                                                                    |


### Alur satu pesan (dijalankan sebagai graf LangGraph)

1. Input masuk: suara diubah ke teks (STT), foto makanan atau struk dibaca model vision, teks langsung diteruskan.
2. LLM mengekstrak ke JSON terstruktur (item makanan, porsi, jam tidur, aktivitas) dengan skema tetap.
3. Log disimpan, ringkasan dan state diperbarui bila perlu.
4. Konteks dirakit dari lapisan di atas.
5. LLM menjawab dan memanggil tool saat butuh angka.
6. Guardrail memeriksa keluaran (tidak ada saran obat, tidak ada klaim diagnosis, tanda bahaya dialihkan).
7. Jawaban dikirim ke aplikasi atau WhatsApp.

### Contoh diskusi: "Mau makan rendang malam ini, boleh berapa?"

1. LLM memanggil `sisa_target_harian()`: sisa lemak dan garam hari ini dihitung dari log makan siang.
2. LLM memanggil `cari_gizi("rendang", porsi)` untuk beberapa ukuran porsi.
3. LLM menjawab dengan porsi yang masih masuk sisa target, ditambah kompensasi: nasi lebih sedikit, tambah sayur, jalan setelah makan.
4. Untuk pengguna dalam mode pengelolaan, jawaban memakai target yang lebih ketat dan menghindari kata "aman"; gunakan "masih sesuai targetmu hari ini".

### Proyeksi, ketidakpastian, dan kapan harus cek

- **Rentang risiko:** input yang belum diketahui (lingkar perut, tensi, gula darah) dihitung untuk nilai terendah dan tertinggi yang masuk akal, sehingga hasilnya berupa rentang skor, bukan satu angka. Versi lanjutan bisa memakai simulasi Monte Carlo.
- **Pemicu cek:** rentang melintasi batas kategori risiko (misalnya bisa "sedang" atau "tinggi"), batas atas masuk kategori tinggi, atau tren kebiasaan 2 minggu memburuk.
- **Cek yang disarankan:** input yang paling mempersempit rentang. Contoh: kalau rentang lebar karena gula darah belum diketahui, sarankan cek gula darah, bukan tensi.
- **Kalibrasi:** hasil cek masuk ke state terstruktur, `hitung_risiko()` dijalankan ulang, dan rentang menyempit. Diagnosis dari dokter mengubah mode ke pengelolaan.

### Risiko pendekatan wrapper dan mitigasinya


| Risiko                           | Mitigasi                                                                                    |
| -------------------------------- | ------------------------------------------------------------------------------------------- |
| Jawaban tidak konsisten          | Temperature rendah, output terstruktur dengan skema JSON, angka hanya dari tool             |
| Halusinasi gizi atau angka medis | LLM dilarang menyebut angka tanpa memanggil tool                                            |
| Biaya token membengkak           | Ringkasan berjalan, log lama diambil hanya bila relevan                                     |
| Latensi lambat saat demo         | Cache respons untuk input demo, model lebih kecil untuk ekstraksi                           |
| Dianggap "cuma ChatGPT"          | Tunjukkan context management, tool calling, dan kalibrasi dari hasil cek di slide teknologi |


## Keamanan klinis, privasi, dan etika

KIRA aman dipakai karena tiga batas yang tegas: tidak mendiagnosis, tidak memberi saran obat, dan selalu mengarahkan ke tenaga medis saat ada tanda bahaya.

**Keamanan klinis**

- Bahasa produk: "proyeksi risiko", "skrining", "saran gaya hidup". Tidak pernah "kamu menderita" atau "kamu aman".
- Saran hanya dari pedoman gaya hidup (kurangi gula/garam, aktivitas fisik, tidur cukup). Obat, dosis, dan penghentian obat tidak pernah disentuh.
- **Deteksi tanda bahaya** berbasis aturan, bukan LLM: tensi sangat tinggi, gula darah sangat tinggi atau sangat rendah, gejala nyeri dada, sesak, lemah separuh badan. Pemicu ini langsung menampilkan pesan untuk segera ke IGD/Puskesmas dan menghentikan alur obrolan biasa. Ambang angka diambil dari pedoman resmi.
- Guardrail LLM: system prompt + daftar topik terlarang + pemeriksaan keluaran sebelum ditampilkan.

**Privasi (UU Pelindungan Data Pribadi)**

- Data kesehatan termasuk data pribadi spesifik, jadi butuh persetujuan eksplisit dan tujuan yang jelas.
- Data minimization: foto makanan diproses lalu dibuang, hanya hasil ekstraksi yang disimpan.
- Enkripsi saat transit dan saat disimpan; pengguna bisa mengekspor dan menghapus datanya.
- Data tidak dibagikan ke pihak ketiga tanpa izin; integrasi Puskesmas/SATUSEHAT hanya atas persetujuan per kali.

**Etika &amp; inklusivitas**

- Hindari menakut-nakuti: proyeksi selalu ditampilkan bersama jalur perbaikan.
- Voice input dan bahasa sederhana untuk pengguna yang tidak nyaman mengetik.
- Transparansi: halaman "bagaimana angka ini dihitung" yang menyebut skor yang dipakai.

**Rekomendasi makanan &amp; aktivitas**

- Porsi dan angka gizi selalu dari tool, bukan tebakan LLM; jawaban menyebut "masih sesuai targetmu hari ini", bukan "aman".
- Pengguna dalam mode pengelolaan mendapat target lebih ketat dan diingatkan untuk mengikuti arahan dokter atau ahli gizi.
- Rekomendasi aktivitas dibatasi pada aktivitas ringan sampai sedang (jalan kaki, naik tangga, peregangan); keluhan nyeri dada, sesak, atau pusing saat aktivitas langsung memicu pesan tanda bahaya.

**Fitur keluarga**

- Keluarga hanya terhubung atas undangan pengguna, dan pengguna memilih apa yang dibagikan (misalnya status check-in dan jadwal kontrol, bukan detail makanan atau hasil lab).
- Akses bisa dicabut kapan saja; anggota keluarga tidak bisa mengubah data pengguna.
- Hindari nada mengawasi: notifikasi ke keluarga berupa ajakan mendukung, bukan laporan pelanggaran.

**WhatsApp tidak resmi (Baileys)**

- Hanya untuk prototype dan demo, dengan nomor khusus dan data dummy.
- Jangan memakai data kesehatan asli melalui kanal tidak resmi; di pitch sebutkan rencana pindah ke WhatsApp Business Platform resmi untuk produksi.

## Skenario demo

Demo live sekitar 4 menit di dalam pitching 10–12 menit, memakai satu persona dengan data 3 minggu yang sudah disiapkan (seed data) plus input live di panggung.

**Persona: Raka, 28 tahun, software engineer.** Kerja sekitar 50 jam/minggu, tidur 5 jam, kopi susu gula aren hampir tiap hari, ayahnya diabetes. Belum pernah cek gula darah.


| Waktu     | Yang ditunjukkan                                                                                                                                      | Yang dilihat juri                                                                                                    |
| --------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------- |
| 0:00–0:30 | Check-in voice live: *"Tadi siang nasi padang rendang, es teh manis, terus begadang sampai jam 2."*                                                   | Suara diubah ke teks, AI mengekstrak menu, gula, jam tidur jadi kartu terstruktur                                    |
| 0:30–0:50 | Foto struk minimarket (disiapkan): kopi susu botol, roti manis, keripik                                                                               | Item struk terbaca dan dihitung gula/garamnya dari tabel gizi lokal                                                  |
| 0:50–1:35 | Layar **Kira-kira 10 Tahun**: kurva risiko diabetes dengan rentang lebar, lalu slider digeser (ganti es teh manis jadi tawar, tidur 1 jam lebih awal) | Kurva kedua turun; muncul "kebiasaan paling berdampak minggu ini"                                                    |
| 1:35–2:20 | Diskusi live di WhatsApp: *"Nanti malam mau makan rendang lagi, boleh berapa?"*                                                                       | AI memanggil tool sisa target harian dan gizi, menjawab porsi + kompensasi; tunjukkan log tool call di layar samping |
| 2:20–2:50 | Notifikasi **"Saatnya cek"**: saran cek gula darah puasa + lokasi Posyandu/CKG terdekat                                                               | Bagian unik: aplikasi tahu kapan dan cek apa yang paling berguna                                                     |
| 2:50–3:30 | Foto hasil cek (kertas hasil disiapkan): gula darah puasa di rentang prediabetes                                                                      | Angka terbaca, rentang risiko menyempit, proyeksi terkalibrasi                                                       |
| 3:30–4:00 | Mode pengelolaan aktif + (opsional) notifikasi dukungan ke anggota keluarga                                                                           | Sistem berubah dari pencegahan ke pendampingan                                                                       |


**Rencana cadangan:** rekam video layar demo penuh; jika internet atau API gagal di panggung, putar rekaman dan lanjutkan narasi. Siapkan juga respons LLM yang di-cache untuk input demo.

**Uji sebelum final:** ulangi demo minimal 5 kali dari HP yang sama yang dipakai di panggung, termasuk dengan sinyal lemah.

## Struktur pitch deck

Deck 12 slide untuk pitching 10–12 menit, mengikuti urutan yang diminta panitia: permasalahan, solusi, inovasi, fitur, dampak, desain, teknologi, demo, dan penggunaan AI.

1. **Judul:** nama KIRA, tagline, nama tim, tema Healthcare subtema 5.
2. **Masalah:** 98,4% diabetes usia 15–29 tidak terdiagnosis; tingkat diagnosis hipertensi 26,9%. Satu kalimat: penyakitnya diam, orangnya merasa sehat.
3. **Persona:** Raka, 28 tahun, dan satu hari dalam hidupnya.
4. **Kenapa solusi sekarang gagal:** aplikasi diet berhenti dipakai, chatbot umum tidak tahu konteks klinis, CKG hanya setahun sekali.
5. **Solusi:** KIRA dalam satu gambar (obrolan → proyeksi → cek → kalibrasi).
6. **Tiga inovasi:** Kira-kira 10 Tahun, tahu kapan harus cek, mode setelah diagnosis.
7. **Demo** (live atau video).
8. **Teknologi &amp; arsitektur:** diagram sistem, graf LangGraph (tanda bahaya dicegat sebelum LLM, angka lewat tools), skor tervalidasi yang dipakai, pembagian AI vs kode.
9. **Keamanan &amp; privasi:** batas klinis, deteksi tanda bahaya, UU PDP.
10. **Dampak &amp; kelayakan:** dukungan untuk CKG/Posyandu, siapa penggunanya, siapa yang membayar (B2C freemium, B2B program wellness kantor, B2G mitra Dinkes), metrik sukses.
11. **Penggunaan AI (wajib):** tabel tools AI beserta perannya, dibagi dua: AI di dalam produk dan AI selama pengembangan.
12. **Penutup:** roadmap singkat dan kalimat penutup.

**Isi slide penggunaan AI (contoh, sesuaikan dengan yang benar-benar dipakai tim):**


| Tool                                              | Dipakai untuk                                                     | Bagian          |
| ------------------------------------------------- | ----------------------------------------------------------------- | --------------- |
| LLM multimodal (sebutkan nama model yang dipakai) | Ekstraksi makanan/tidur dari teks, voice, dan foto; kalimat saran | Di dalam produk |
| Speech-to-text (sebutkan layanan)                 | Mengubah voice note berbahasa campur menjadi teks                 | Di dalam produk |
| OCR (sebutkan library/layanan)                    | Membaca hasil CKG, lab, layar tensimeter                          | Di dalam produk |
| Claude                                            | Riset ide, penyusunan konsep, struktur pitch                      | Pengembangan    |
| Asisten coding (sebutkan)                         | Membantu penulisan dan debugging kode                             | Pengembangan    |


Panitia mewajibkan penggunaan AI dicantumkan di pitch deck, jadi tabel ini harus jujur dan lengkap.

## Naskah video 2 menit

Video maksimal 2 menit, diunggah publik di YouTube. Struktur: hook, masalah, demo, dampak, penutup. Narasi sekitar 250–280 kata.


| Waktu     | Visual                                                      | Narasi                                                                                                                         |
| --------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| 0:00–0:10 | Raka di meja kerja larut malam, kopi susu di samping laptop | "Umurku 28. Aku merasa sehat. Aku belum pernah cek gula darah."                                                                |
| 0:10–0:25 | Teks angka besar di layar                                   | "Di Indonesia, hampir semua kasus diabetes di usia 15 sampai 29 tahun tidak terdiagnosis. Penyakitnya diam, sampai terlambat." |
| 0:25–0:45 | Screen recording: Raka kirim voice note ke KIRA             | "KIRA cukup diajak ngobrol satu menit sehari. Ceritakan makanmu, minummu, tidurmu, pakai bahasamu sendiri."                    |
| 0:45–1:05 | Layar Kira-kira 10 Tahun, slider digeser, kurva turun       | "KIRA menunjukkan dua masa depan: kalau kebiasaanmu tetap, dan kalau kamu ubah satu hal kecil."                                |
| 1:05–1:25 | Notifikasi "Saatnya cek" + peta Posyandu                    | "Yang paling penting, KIRA tahu kapan kamu harus memeriksakan diri, dan cek apa yang paling berguna."                          |
| 1:25–1:45 | Foto hasil cek, pita risiko menyempit, mode pengelolaan     | "Setelah hasilnya masuk, KIRA belajar dari data nyatamu dan mendampingi langkah berikutnya bersama doktermu."                  |
| 1:45–2:00 | Logo, tagline, nama tim                                     | "KIRA. Kira-kira kesehatanmu 10 tahun lagi seperti apa? Tanya KIRA."                                                           |


**Catatan produksi:** rekam layar di resolusi tinggi, pakai subtitle (banyak juri menonton tanpa suara), dan tidak perlu semua anggota tim tampil di satu frame.

## Antisipasi pertanyaan juri


| Pertanyaan                                          | Jawaban inti                                                                                                                                                                                                                                                                            |
| --------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ini cuma wrapper ChatGPT?                           | LLM dipakai untuk percakapan, tapi nilai produknya ada di context management (profil, state kesehatan, ringkasan, log), tool kalkulator untuk angka, dan kalibrasi dari hasil pemeriksaan nyata. ChatGPT biasa tidak menyimpan state kesehatan terstruktur dan tidak menghitung risiko. |
| Apa bedanya dengan aplikasi diet?                   | Bukan pencatat kalori: KIRA memproyeksikan risiko dari skor tervalidasi, bisa diajak diskusi porsi, dan tahu kapan pengguna harus cek.                                                                                                                                                  |
| Model forecasting-nya dilatih pakai data apa?       | Tidak dilatih dari nol. Angka risiko dari FINDRISC dan Framingham Hypertension yang sudah divalidasi, dipanggil LLM sebagai tool. Pendekatan ini bisa dijelaskan dan diaudit.                                                                                                           |
| Seakurat apa proyeksinya?                           | Akurasi mengikuti skor dasarnya. Karena itu KIRA menampilkan rentang, bukan satu angka, dan mendorong pengukuran nyata saat rentangnya terlalu lebar.                                                                                                                                   |
| Bagaimana kalau LLM salah menghitung porsi rendang? | LLM tidak menghitung: porsi dan gizi dari tool berbasis Tabel Komposisi Pangan Indonesia dan sisa target harian. LLM hanya merangkai jawabannya.                                                                                                                                        |
| Data self-report kan tidak akurat?                  | Betul, makanya data klinis jadi jangkar. Self-report dipakai untuk tren dan what-if; hasil cek menggantikan tebakan.                                                                                                                                                                    |
| Bagaimana kalau AI salah memberi saran?             | Saran dibatasi pada pedoman gaya hidup, tidak menyentuh obat. Tanda bahaya dideteksi aturan, bukan LLM, dan langsung diarahkan ke fasilitas kesehatan.                                                                                                                                  |
| WhatsApp-nya pakai API tidak resmi?                 | Ya, hanya untuk prototype dengan data dummy. Untuk produksi pindah ke WhatsApp Business Platform resmi demi keamanan data dan kepatuhan.                                                                                                                                                |
| Fitur keluarga tidak melanggar privasi?             | Hanya atas undangan pengguna, pengguna memilih data yang dibagikan, dan akses bisa dicabut kapan saja.                                                                                                                                                                                  |
| Orang akan berhenti pakai setelah seminggu?         | Check-in lewat suara, foto, atau WhatsApp dalam 1 menit, dan grafik what-if memberi alasan untuk kembali.                                                                                                                                                                               |
| Siapa yang membayar?                                | Freemium untuk individu; program wellness kantor (B2B); kemitraan Dinkes/Puskesmas untuk menindaklanjuti peserta CKG (B2G).                                                                                                                                                             |
| Kenapa tidak cukup CKG saja?                        | CKG memotret kondisi setahun sekali. KIRA mengisi 364 hari di antaranya dan mengarahkan orang kembali ke CKG atau Posyandu saat dibutuhkan.                                                                                                                                             |


## Rencana pengerjaan &amp; checklist submission

Pengumpulan ditutup Oct 16, 2026 pukul 23.50 WIB. Targetkan submit beberapa jam lebih awal untuk berjaga-jaga dari masalah upload.

**Pembagian peran (4 orang)**


| Peran              | Tanggung jawab                                                                         |
| ------------------ | -------------------------------------------------------------------------------------- |
| AI/ML              | Pipeline ekstraksi LLM, pemetaan tabel gizi, mesin skor risiko + Monte Carlo + what-if |
| Backend            | API, database, OCR hasil cek, autentikasi, deploy                                      |
| Frontend           | Chat/voice UI, layar Kira-kira 10 Tahun dengan slider, layar rekomendasi cek           |
| Produk &amp; pitch | Desain UI/UX, seed data persona, pitch deck, video, README, proposal                   |


**Prioritas pengerjaan:** urutan kerja, pembagian tugas per fase, dan fitur yang boleh dipotong ada di Plan implementasi.

**Checklist submission**

- Video maksimal 2 menit, YouTube publik
- Repository GitHub dengan README.md (alur dan cara menjalankan solusi)
- Pitch deck PDF dengan slide penggunaan AI
- Prototype (link aplikasi/website yang bisa dicoba)
- Proposal PDF A4 maksimal 10 halaman, opsional tapi disarankan karena menjadi bahan penilaian penyisihan
- Cek ulang: tidak ada data pribadi asli di seed data atau screenshot