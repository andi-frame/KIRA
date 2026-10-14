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

## Yang BELUM bersumber (jujur)

- **Gula** semua makanan: TKPI tidak memuat gula. Semua nilai gula adalah estimasi KIRA dan ditandai "gula: estimasi" di `foods.source_note`.
- **Natrium** pada beberapa makanan TKPI (mis. rendang, soto betawi, gudeg): TKPI tidak menyediakannya; dipakai estimasi dan ditandai.
- **Porsi khas** (`default_portion_g`): estimasi KIRA (TKPI tidak memuat ukuran porsi).
- **~60 makanan lain** (nasi goreng, es teh manis, kopi susu gula aren, boba, dsb.) tidak punya padanan langsung di TKPI: semua nilainya estimasi KIRA dan ditandai.
- **Kosakata gejala tanda bahaya** (`RED_FLAG_KEYWORDS` dan aturan di `red_flags.py`): daftar gejala dari praktik umum, bukan dari dokumen. Tanda bahayanya sendiri (nyeri dada, sesak, tanda stroke, pingsan, kejang) sejalan dengan pedoman, tetapi ejaan dan frasa adalah keputusan KIRA.
- **Interpolasi p10**: lihat tabel.

Aplikasi menampilkan sumber ini kepada pengguna di "Bagaimana angka ini dihitung?", dan tool `cari_gizi` mengembalikan field `sumber` per makanan.
