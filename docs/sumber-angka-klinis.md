# Sumber angka klinis KIRA

Diperiksa 2026-10-15. Kode: `backend/app/core_calc/constants.py`, `backend/seed/tkpi_2017.json`, `backend/seed/foods.json`.
Status: **Primer** = dibaca langsung dari dokumen resmi; **Sekunder** = dikutip dari sumber yang merujuk dokumen asli;
**Asumsi KIRA** = keputusan produk, bukan angka dari pedoman.

| Angka | Nilai di kode | Sumber | Status |
|---|---|---|---|
| Poin FINDRISC (usia, IMT, lingkar perut pria/wanita, aktivitas, sayur/buah, obat hipertensi, gula tinggi, riwayat keluarga) | `FINDRISC_POINTS` | Lindström & Tuomilehto, *Diabetes Care* 2003;26:725. Tabel poin dikonfirmasi di Jølle dkk., *BMJ Open Diabetes Res Care* 2019 ([PMC6887494](https://pmc.ncbi.nlm.nih.gov/articles/PMC6887494/)) | Primer (artikel HUNT3); paper 2003 tidak dibaca langsung |
| Kategori skor 0-6, 7-11, 12-14, 15-20, 21-26 | `FINDRISC_CATEGORIES` | PMC6887494 | Primer |
| Cut-off IMT/lingkar perut | Asli (Eropa) | Versi Indonesia dengan klasifikasi IMT/lingkar perut yang dimodifikasi tidak lebih akurat: AUC 0,73 (standar) vs 0,72 ([PLoS ONE 2022, PMC9302803](https://pmc.ncbi.nlm.nih.gov/articles/PMC9302803/)) | Primer (abstrak) |
| Insidensi 10 tahun per kategori: 1%, 4%, 17%, 33%, 50% | `P10_BY_CATEGORY` | Estimasi resmi formulir FINDRISC (1 dari 100, 25, 6, 3, 2), dikutip di [LOINC 97064-0](https://findacode.com/loinc/97064-0--total-risk-score-findrisc.html) | **Sekunder** |
| Catatan kejujuran untuk angka di atas | pengungkapan di app | Kohort modern lebih rendah: HUNT3 Norwegia, skor ≥15 → 13,5% (PMC6887494); definisi outcome berbeda (obat penurun gula) | Primer |
| Interpolasi linear antar skor tengah kategori | `findrisc.p10` | — | **Asumsi KIRA** (agar perubahan kebiasaan terlihat; diungkapkan di app) |
| Hipertensi ≥140/90; "prehipertensi (normal tinggi)" 130-139 / 85-89 | `BP_THRESHOLDS` | Keputusan Menkes HK.01.07/MENKES/303/2026, PNPK Hipertensi Dewasa ([PDF](https://keslan.kemkes.go.id/unduhan/fileunduhan1780387327_362636.pdf)) | Primer |
| Tanda bahaya tensi ≥180 dan/atau ≥110 (hipertensi derajat 3) | `RED_FLAG_BP = (180, 110)` | KMK 303/2026 (definisi hipertensi emergensi: derajat 3 + kerusakan organ akut) | Primer |
| Prediabetes GDP 100-125, HbA1c 5,7-6,4; diabetes GDP ≥126, HbA1c ≥6,5; sewaktu ≥200 dengan keluhan | `GLUCOSE_HIGH_*` | PERKENI 2021, Tabel 3-4 ([PDF](https://pbperkeni.or.id/wp-content/uploads/2021/11/22-10-21-Website-Pedoman-Pengelolaan-dan-Pencegahan-DMT2-Ebook.pdf)) | Primer |
| Hipoglikemia < 70 mg/dL (level 2 < 54) | `RED_FLAG_GLUCOSE["low"] = 70` | PERKENI 2021 (mengutip ADA 2020) | Primer |
| Hiperglikemia berat: KAD 300-600, SHH > 600 mg/dL, perlu perawatan RS | `RED_FLAG_GLUCOSE["high"] = 300` | PERKENI 2021, bagian Krisis Hiperglikemia | Primer (ambang peringatan 300 = awal rentang KAD) |
| Batas harian gula 50 g, natrium 2000 mg, lemak 67 g | `DAILY_LIMITS` | Permenkes 30/2013 Pasal 4 ayat (2) ([teks](https://pasal.id/peraturan/permen/permenkes-no-30-tahun-2013)); diubah Permenkes 63/2015 | Primer (teks asli; konsolidasi perubahan tidak diperiksa) |
| Mode pengelolaan: gula 25 g | `DAILY_LIMITS_MANAGEMENT` | WHO 2015: gula bebas <10% energi; <5% (~25 g) rekomendasi bersyarat untuk manfaat tambahan ([siaran WHO](https://www.who.int/news/item/04-03-2015-who-calls-on-countries-to-reduce-sugars-intake-among-adults-and-children)) | Sekunder; angka mode pengelolaan = **asumsi KIRA** (tidak ada angka resmi Indonesia yang lebih ketat) |
| Energi, lemak, karbohidrat, natrium per 100 g untuk 38 makanan | `seed/tkpi_2017.json` | TKPI 2017 Kemenkes ([panganku.org](https://www.panganku.org)), kode pangan disimpan per baris | Primer |

| Ambang jalan intensitas sedang 100 langkah/menit (untuk menit aktif dari Health Connect) | `MODERATE_CADENCE` di `core_calc/steps.py` | Tudor-Locke dkk., *Int J Behav Nutr Phys Act* 2019;16:8, CADENCE-adults, usia 21-40 tahun (nilai heuristik; model regresi 102, ROC 96) | Sekunder (abstrak dan ringkasan; makalah penuh tidak dibaca); pemakaian di luar 21-40 tahun adalah perkiraan KIRA |
| Penanda triase: rentang diabetes GDP >=126, sewaktu >=200, HbA1c >=6,5; prediabetes GDP 100-125, HbA1c 5,7-6,4; tensi >=140/90 hipertensi, 130-139/85-89 normal-tinggi | `core_calc/triage.py`, `constants.py` | PERKENI 2021 Tabel 3-4; KMK 303/2026 | Primer; kata-kata penanda dan urutan tingkat adalah keputusan KIRA, bukan diagnosis |
| Gula, natrium, lemak, kalori dari foto label kemasan | `core_calc/label.py` | Angka tercetak di kemasan, dibaca model visi dan divalidasi (gula/lemak tidak boleh melebihi berat sajian; kalori maks. 9 kkal/g; natrium maks. 400 mg/g) | Primer dari label produk; kesalahan baca foto mungkin, jadi nilai mustahil ditolak dan koreksi porsi tersedia |

| Protokol tensi di rumah: 7 hari (minimal 3), pagi dan malam, 2 bacaan berjarak 1 menit; buang hari pertama; rata-rata >= 135/85 mmHg = rentang hipertensi | `HBPM_*` di `constants.py`, `core_calc/hbpm.py` | Stergiou G dkk., 2021 ESH Practice Guidelines for office and out-of-office blood pressure measurement, *J Hypertens* 2021;39:1293-1302, Box 6 dan 7 ([teks lengkap](https://www.grupohospitalariohc.com/wp-content/uploads/2021/04/2021_European_Society_of_Hypertension_practice.96700.pdf)) | Primer (dibaca langsung). "Minimal 12 bacaan" dihitung SETELAH hari pertama dibuang: tafsir KIRA yang lebih ketat dari Box 7 |
| Gizi produk kemasan dari kode batang (gula, natrium, lemak, energi per 100 g/ml) | `services/barcode.py` | Open Food Facts, basis data terbuka lisensi ODbL, disumbangkan pengguna ([dokumentasi API](https://openfoodfacts.github.io/openfoodfacts-server/api/)); batas 15 permintaan/menit/IP untuk pembacaan produk | Sekunder (data komunitas): nilai mustahil ditolak oleh `core_calc/label.py`, data tidak lengkap ditandai, dan sumbernya selalu ditampilkan |
| Kebutuhan energi dewasa per kelompok umur: laki-laki 19-29 th 2.650, 30-49 th 2.550, 50-64 th 2.150, 65-80 th 1.800, 80+ 1.600 kkal; perempuan 19-29 th 2.250, 30-49 th 2.150, 50-64 th 1.800, 65-80 th 1.550, 80+ 1.400 kkal | `AKG_ENERGY_KCAL` di `constants.py`, `core_calc/planner.py` | Permenkes 28/2019 tentang AKG, Lampiran I Tabel 1 (salinan resmi [JDIH BPK](https://peraturan.bpk.go.id/Details/138621/permenkes-no-28-)); faktor aktivitas fisik 1,26 (4-64 th) dan 1,12 (lansia) sudah termasuk (catatan kaki 2). Hamil/menyusui di luar cakupan | **Primer** (tabel dibaca langsung dari lampiran, 2026-10-16) |
| Aktivitas 150 menit/minggu intensitas sedang, penguatan otot >= 2 hari/minggu | `EXERCISE_WEEKLY_TARGET`, `core_calc/habits.py`, `core_calc/planner.py` | WHO 2020 Guidelines on physical activity and sedentary behaviour (sama dengan target mingguan di `core_calc/goals.py`) | Primer (sudah dipakai sejak Fase 5) |
| Target tidur 7-9 jam | `SLEEP_TARGET_RANGE` | Konsensus AASM/SRS (Watson dkk. 2015) | Sekunder (ringkasan); target 8 jam bila rata-rata terkini < 7 jam adalah **asumsi KIRA** |
| Gizi 48 bahan/komponen hidangan (timun, sambal, ayam goreng tepung, lele goreng, kecap manis, ...) | `seed/components.json`, dibuat oleh `seed/fetch_components.py` | Energi, lemak, karbohidrat, natrium dari TKPI 2017 ([panganku.org](https://www.panganku.org), kode per baris) bila ada padanan; gula (TKPI tidak memuatnya) dan bahan tanpa padanan TKPI dari USDA FoodData Central SR Legacy (domain publik, fdcId per baris). Asal tiap angka tertulis di `source_note` | Primer untuk TKPI dan USDA; padanan USDA untuk bahan Indonesia (mis. lele goreng = channel catfish breaded and fried) adalah **pilihan KIRA** dan ditulis di `source_note` |
| Batas "tidur pendek" < 6 jam untuk perbandingan pola | `SHORT_SLEEP_HOURS` di `core_calc/patterns.py` | Konsensus AASM/SRS: dewasa disarankan tidur >= 7 jam (Watson dkk., *J Clin Sleep Med* 2015;11:591) | Konsensus dibaca dari ringkasan; **batas 6 jam adalah keputusan KIRA** mengikuti kategori yang lazim di studi epidemiologi |

## Yang BELUM bersumber (jujur)

- **Gula** semua makanan: TKPI tidak memuat gula. Semua nilai gula adalah estimasi KIRA dan ditandai "gula: estimasi" di `foods.source_note`.
- **Natrium** pada beberapa makanan TKPI (mis. rendang, soto betawi, gudeg): TKPI tidak menyediakannya; dipakai estimasi dan ditandai.
- **Porsi khas** (`default_portion_g`): estimasi KIRA (TKPI tidak memuat ukuran porsi).
- **~60 makanan lain** (nasi goreng, es teh manis, kopi susu gula aren, boba, dsb.) tidak punya padanan langsung di TKPI: semua nilainya estimasi KIRA dan ditandai.
- **Kosakata gejala tanda bahaya** (`RED_FLAG_KEYWORDS` dan aturan di `red_flags.py`): daftar gejala dari praktik umum, bukan dari dokumen. Tanda bahayanya sendiri (nyeri dada, sesak, tanda stroke, pingsan, kejang) sejalan dengan pedoman, tetapi ejaan dan frasa adalah keputusan KIRA.
- **Interpolasi p10**: lihat tabel.
- **Arah tren hasil pemeriksaan** (naik/turun/stabil): selisih pengukuran pertama dan terakhir dibandingkan ambang derau KIRA (tensi sistolik 5 mmHg, diastolik 3, gula puasa 10 mg/dL, sewaktu 20, HbA1c 0,3 poin). Bukan ambang klinis; hanya untuk meredam variasi pengukuran biasa.
- **Menit aktif dari langkah**: dihitung dari segmen dengan kadensi rata-rata >= 100 langkah/menit; jalan santai yang panjang tidak dihitung, jadi cenderung konservatif. Batas kadensi mustahil (250 langkah/menit) dan pemilihan satu sumber data adalah keputusan KIRA.
- **Ambang perubahan rekap mingguan** (gula 2 g, minuman manis 0,2, aktif 3 menit dianggap "hampir sama"): keputusan KIRA untuk meredam derau harian, bukan angka klinis.

- **Waktu tindak lanjut "Saatnya cek"** (tanya setelah 3 hari, jarak 4 hari, maksimal 2 kali, tunda 3 hari, tahan 14 hari setelah "sudah dicek" tanpa hasil dan 30 hari setelah "tidak perlu"): keputusan produk KIRA agar tidak menagih, bukan angka klinis.
- **Perbandingan pola tidur**: minimal 3 hari di tiap kelompok; selisih rata-rata dua kelompok, bukan uji statistik dan bukan sebab-akibat. Selalu disertai catatan itu.
- **Pengingat lokal**: jam 19.00 (check-in) dan Senin 08.00 (rekap) hanyalah bawaan yang bisa diubah pengguna; bukan rekomendasi klinis.
- **Komponen tanpa sumber sama sekali** (ditandai "Estimasi KIRA" di `source_note`): sambal bawang, sambal terasi, kecap manis (TKPI NP005 adalah kecap biasa dengan karbohidrat 9 g, jadi tidak dipakai untuk kecap manis), bawang goreng; serta gula untuk ayam goreng tepung, lele goreng, tempe, kerupuk udang, emping, dan natrium emping.
- **Gram per komponen hidangan** (`seed/dishes.json`, 28 hidangan: ayam geprek = ayam goreng tepung 100 g + nasi 150 g + sambal 25 g + timun 30 g, dst.): perkiraan resep rumahan/warung oleh KIRA, bukan hasil penimbangan. Gizi tiap komponen tetap dari tabel pangan; pengguna dapat mengubah gram tiap komponen.
- **Pembagian per waktu makan** (sarapan 25%, siang 35%, malam 30%, selingan 10% dari energi dan batas harian), toleransi energi 15% di atas anggaran waktu makan, dan **defisit 400 kkal** (tengah rentang 300-500) untuk tujuan menurunkan berat bila IMT >= 25 dengan lantai 1.500/1.200 kkal: asumsi KIRA, bukan terapi gizi medis; aplikasi menyebutnya dan menyarankan ahli gizi.
- **Tanjakan olahraga**: mulai dari max(30, 1,2 x rata-rata mingguan 2 minggu terakhir) menit, naik paling banyak 20% per minggu sampai 150: asumsi KIRA.
- **Energi bawaan 2.150 kkal** bila umur/jenis kelamin belum diisi (AKG perempuan 30-49 tahun): asumsi KIRA, ditandai di aplikasi.
- **Sinyal kebiasaan Beranda** (`core_calc/habits.py`): "perhatian" bila batas harian terlewati pada >= 3 dari 7 hari atau rata-ratanya di atas batas, "pantau" bila 1-2 hari; tidur "perhatian" bila >= 3 malam < 6 jam; data dianggap kurang bila < 3 hari tercatat dalam 7 hari. Ambang batas harian sendiri bersumber (Permenkes 30/2013, WHO 2020, AASM), tetapi pengelompokan tingkatnya keputusan KIRA.
- **Langkah berikutnya di Beranda** (jam sarapan dianggap terlewat setelah 10.00, siang 14.00, malam 20.00; sisa 30 menit gerak per hari = 150/5): keputusan produk KIRA.
- **Pencocokan nama makanan** (indeks n-gram karakter, ambang 0,7 dengan selisih 0,1 dari kandidat kedua; hidangan 0,85): keputusan teknis KIRA dari uji pada data seed; bila ragu sistem tidak menebak (catatan "belum ada di database gizi").

Aplikasi menampilkan sumber ini kepada pengguna di "Bagaimana angka ini dihitung?", dan tool `cari_gizi` mengembalikan field `sumber` per makanan.

## Statistik masalah (untuk deck, video, dan proposal)

Diperiksa 2026-10-15. Hanya angka berstatus **Primer** atau **Sekunder (konsisten)** yang dipakai di materi submission; sisanya dibuang.

| Klaim | Angka | Sumber | Status |
|---|---|---|---|
| Prevalensi diabetes usia ≥15 tahun | 11,7% menurut pemeriksaan gula darah, 2,2% menurut diagnosis dokter; selisih 9,5 poin. Hitungan KIRA dari dua angka itu: sekitar 4 dari 5 kasus belum terdiagnosis ((11,7 - 2,2) / 11,7 = 81%) | Kemenkes, [Hasil Utama SKI 2023](https://www.badankebijakan.kemkes.go.id/daftar-frequently-asked-question-seputar-hasil-utama-ski-2023/hasil-utama-ski-2023/) | Primer |
| Diabetes tidak terdiagnosis pada usia muda | 98,4% pada usia 15-29 tahun (data **Riskesdas 2018**, bukan SKI 2023) | Ferdina dkk., *J ASEAN Fed Endocr Soc* 2025;40(1):53-60, dikutip [Alomedika](https://alomedika.com/diabetes-yang-luput-dari-diagnosis-di-indonesia-telaah-jurnal-alomedika) | Sekunder (makalah asli tidak dibaca; sebut tahun datanya) |
| Tingkat diagnosis hipertensi 2023 | 26,9% (33,0% pada 2013, 24,1% pada 2018) | Muharram, Widyahening, Danaei, [*BMJ Open* 2025;15(12):e109588](https://bmjopen.bmj.com/content/15/12/e109588) | Primer (abstrak) |
| Hipertensi baru terdeteksi di CKG 2026 | Sekitar 1 juta kasus baru dari 9,2 juta peserta yang tahun sebelumnya tidak hipertensi (pemeriksaan ulang) | Kemenkes, [Hasil CKG 2026](https://www.kemkes.go.id/id/hasil-ckg-2026-1-juta-warga-yang-semula-sehat-kini-terdeteksi-hipertensi), 4 Agustus 2026 | Primer |
| Hipertensi dan prehipertensi di CKG 2026 | 4,9 juta hipertensi dan 5,5 juta prehipertensi dari sekitar 52 juta dewasa | Dilaporkan media yang mengutip Kemenkes (RRI, Okezone, CNA); tidak ada di rilis Kemenkes yang dibaca | Sekunder |
| Obesitas sentral usia ≥15 tahun | 36,8% (2023) | Dikutip jurnal analisis SKI 2023 dan media; laporan resmi tidak dibuka langsung | Sekunder |
| Beban BPJS gagal ginjal 2025 | Rp13,3 triliun (peringkat 2 penyakit katastropik; jantung Rp17,3 triliun) | [detikHealth](https://health.detik.com/infografis/d-8632282/infografis-daftar-penyakit-katastropik-yang-jadi-beban-anggaran-terbesar-bpjs-di-2025), konsisten di beberapa media | Sekunder |

**Dibuang dari materi karena tidak terverifikasi atau bertentangan:**

- Angka diabetes CKG 2026 (992 ribu dan 1,9 juta prediabetes versus 1,19 juta dan 2,49 juta di sumber lain; penyebutnya berbeda).
- "Baru 10-15 juta terdiagnosis" (tidak ditemukan sumber; gunakan 2,2% vs 11,7% dari SKI 2023).
- 64,9% berhenti minum obat hipertensi karena merasa sehat (hanya ditemukan di bab skripsi).
- Obesitas sentral 30,8% pada 2018 (tidak diverifikasi).
