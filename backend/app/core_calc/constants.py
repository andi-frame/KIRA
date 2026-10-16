"""Konstanta klinis KIRA beserta sumbernya.

Setiap blok menyebut sumber dan status verifikasi (diperiksa 2026-10-15). Rincian dan tautan lengkap ada di
docs/sumber-angka-klinis.md. Yang BUKAN dari sumber (asumsi produk) ditandai ASUMSI KIRA.
"""

# FINDRISC: poin tiap faktor. Band = daftar (batas_atas_eksklusif, poin) berurutan; nilai di atas band
# terakhir mendapat "top". Batas IMT/lingkar perut memakai +0.05 agar nilai tepat di batas atas masuk band
# bawah (keduanya dibulatkan 1 desimal).
# SUMBER (terverifikasi): Lindstrom & Tuomilehto, Diabetes Care 2003; tabel poin dikonfirmasi lewat
# Jolle et al., BMJ Open Diabetes Res Care 2019 (HUNT3), PMC6887494. Memakai cut-off ASLI (Eropa) karena
# itulah yang tervalidasi; versi Indonesia dengan klasifikasi IMT/lingkar perut yang dimodifikasi tidak lebih
# akurat (Translation and performance of the FINDRISC in the Indonesian population, PLoS ONE 2022, PMC9302803:
# AUC 0,73 untuk versi standar vs 0,72 untuk versi modifikasi).
FINDRISC_POINTS = {
    "age": {"bands": [(45, 0), (55, 2), (65, 3)], "top": 4},
    "bmi": {"bands": [(25.0, 0), (30.05, 1)], "top": 3},
    "waist": {
        "male": {"bands": [(94.0, 0), (102.05, 3)], "top": 4},
        "female": {"bands": [(80.0, 0), (88.05, 3)], "top": 4},
    },
    "activity_no": 2,
    "veg_fruit_no": 1,
    "bp_medication_yes": 2,
    "high_glucose_yes": 5,
    "family_history": {"none": 0, "second_degree": 3, "first_degree": 5},
}

# SUMBER (terverifikasi): kategori skor FINDRISC 0-6, 7-11, 12-14, 15-20, 21-26 (HUNT3, PMC6887494).
FINDRISC_CATEGORIES = [
    (0, 6, "low"),
    (7, 11, "slightly_elevated"),
    (12, 14, "moderate"),
    (15, 20, "high"),
    (21, 26, "very_high"),
]

# Perkiraan insidensi diabetes 10 tahun per kategori: 1 dari 100, 1 dari 25, 1 dari 6, 1 dari 3, 1 dari 2.
# SUMBER (terverifikasi sekunder): estimasi resmi formulir FINDRISC dari kohort Finlandia, dikutip di LOINC 97064-0.
# CATATAN KEJUJURAN: kohort modern lebih rendah (HUNT3 Norwegia: skor >=15 -> 13,5% bukan ~30%; outcome berbeda,
# yaitu pembelian obat penurun gula). KIRA memakai estimasi resmi dan mengungkapkannya di aplikasi.
# ASUMSI KIRA: nilai di antara kategori diinterpolasi linear antar skor tengah kategori (lihat findrisc.p10).
P10_BY_CATEGORY = {
    "low": 0.01,
    "slightly_elevated": 0.04,
    "moderate": 0.17,
    "high": 0.33,
    "very_high": 0.50,
}

# Tekanan darah: SUMBER (terverifikasi, primer): Keputusan Menkes HK.01.07/MENKES/303/2026 (PNPK Hipertensi
# Dewasa; klasifikasi mengadopsi ESC): normal-tinggi ("prehipertensi") 130-139 / 85-89; hipertensi >=140/90
# (derajat 1: 140-159/90-99, derajat 2: 160-179/100-109, derajat 3: >=180/>=110).
# Pasangan = (sistolik minimum, diastolik minimum); salah satu terpenuhi.
BP_THRESHOLDS = {
    "hypertension": (140, 90),
    "prehypertension": (130, 85),
}

# Tensi di rumah (HBPM). SUMBER (primer, dibaca langsung): Stergiou G dkk., 2021 European Society of Hypertension Practice
# Guidelines for office and out-of-office blood pressure measurement, J Hypertens 2021;39:1293-1302, Box 6 (jadwal) dan
# Box 7 (penilaian): ukur 7 hari (minimal 3 hari), pagi dan malam, 2 kali tiap sesi berjarak 1 menit; nilai 7 hari
# (minimal 3 hari dengan minimal 12 bacaan), buang hari pertama, rata-ratakan sisanya; rata-rata >=135/85 mmHg = rentang hipertensi.
# ASUMSI KIRA: "minimal 12 bacaan" dihitung SETELAH hari pertama dibuang (tafsir yang lebih ketat dari Box 7).
HBPM_HOME_THRESHOLD = (135, 85)  # (sistolik, diastolik): salah satu terpenuhi
HBPM_PROTOCOL_DAYS = 7
HBPM_MIN_DAYS = 3
HBPM_MIN_READINGS = 12

# Tanda bahaya.
# BP: hipertensi derajat 3 (>=180 dan/atau >=110) = kandidat krisis hipertensi, KMK 303/2026 (primer).
# Gula darah rendah: hipoglikemia < 70 mg/dL, PERKENI 2021 hlm. 53 (mengikuti ADA); < 54 = level 2.
# Gula darah tinggi: PERKENI 2021 menyebut KAD pada glukosa 300-600 mg/dL dan SHH > 600, keduanya butuh
# perawatan rumah sakit; ambang peringatan KIRA = 300.
RED_FLAG_BP = (180, 110)  # (sistolik, diastolik): salah satu terpenuhi
RED_FLAG_GLUCOSE = {"high": 300, "low": 70}  # mg/dL; rendah = di bawah nilai ini
# ASUMSI KIRA: kosakata gejala (nyeri dada, sesak, tanda stroke, pingsan, kejang). Aturan, bukan LLM.
RED_FLAG_KEYWORDS = [
    "nyeri dada",
    "dada sakit",
    "dada sesak",
    "sesak napas",
    "sesak nafas",
    "sulit bernapas",
    "lemah separuh badan",
    "separuh badan lemas",
    "wajah perot",
    "bicara pelo",
    "pingsan",
    "kejang",
]

# Gula darah "pernah tinggi" untuk faktor FINDRISC. SUMBER (terverifikasi, primer): PERKENI 2021 Tabel 3-4:
# prediabetes GDP 100-125 mg/dL, HbA1c 5,7-6,4 %; diabetes GDP >=126, HbA1c >=6,5 %, glukosa sewaktu >=200
# (dengan keluhan klasik). Glukosa sewaktu < 200 tidak punya kategori sendiri, jadi ambangnya 200.
GLUCOSE_HIGH_FASTING = 100
GLUCOSE_HIGH_RANDOM = 200
GLUCOSE_HIGH_HBA1C = 5.7  # persen

# Batas konsumsi harian: SUMBER (terverifikasi): Permenkes 30/2013 Pasal 4 ayat (2): gula > 50 g,
# natrium > 2000 mg, lemak total > 67 g per orang per hari berisiko hipertensi, stroke, diabetes, serangan jantung
# (diubah Permenkes 63/2015). Lihat juga PP 28/2024.
DAILY_LIMITS = {"sugar_g": 50.0, "sodium_mg": 2000.0, "fat_g": 67.0}
# Mode pengelolaan: gula 25 g (~5% energi, rekomendasi bersyarat WHO 2015 untuk manfaat tambahan); natrium dan
# lemak tetap sama. ASUMSI KIRA: tidak ada angka resmi Indonesia yang lebih ketat; ikuti arahan dokter/ahli gizi.
DAILY_LIMITS_MANAGEMENT = {"sugar_g": 25.0, "sodium_mg": 2000.0, "fat_g": 67.0}

# Rentang diabetes untuk penanda triase (bukan diagnosis). SUMBER (primer): PERKENI 2021 Tabel 3-4: GDP >=126 mg/dL,
# HbA1c >=6,5 %, glukosa sewaktu >=200 mg/dL (dengan keluhan klasik) berada di rentang diabetes; prediabetes memakai
# GLUCOSE_HIGH_FASTING dan GLUCOSE_HIGH_HBA1C di atas (batas atas prediabetes: GDP 125, HbA1c 6,4).
GLUCOSE_DIABETES_FASTING = 126
HBA1C_DIABETES = 6.5
# ASUMSI KIRA: selisih pengukuran pertama dan terakhir di bawah ini dianggap "stabil" (derau pengukuran harian).
TREND_NOISE = {"sys": 5.0, "dia": 3.0, "fasting_glucose": 10.0, "random_glucose": 20.0, "hba1c": 0.3, "waist": 2.0, "resting_heart_rate": 5.0}

# Kebutuhan energi per kelompok umur dewasa (kkal/hari). SUMBER (terverifikasi, primer): Permenkes 28/2019 tentang
# Angka Kecukupan Gizi, Lampiran I Tabel 1 (dibaca dari salinan resmi JDIH BPK, peraturan.bpk.go.id/Details/138621,
# 2026-10-16). Nilai untuk berat/tinggi rujukan tiap kelompok; faktor aktivitas fisik 1,26 (4-64 th) dan 1,12 (lansia)
# sudah termasuk (catatan kaki 2). Tambahan hamil/menyusui di luar cakupan KIRA.
# (umur_min, umur_maks_inklusif, energi): umur di atas kelompok terakhir memakai kelompok terakhir.
AKG_ENERGY_KCAL = {
    "male": [(19, 29, 2650), (30, 49, 2550), (50, 64, 2150), (65, 80, 1800), (81, 200, 1600)],
    "female": [(19, 29, 2250), (30, 49, 2150), (50, 64, 1800), (65, 80, 1550), (81, 200, 1400)],
}
# ASUMSI KIRA (bukan terapi gizi medis): bila IMT >= 25 dan tujuan menurunkan berat, kurangi 400 kkal/hari (tengah
# rentang 300-500 yang lazim), tidak di bawah 1.500 kkal (laki-laki) / 1.200 kkal (perempuan). Arahkan ke ahli gizi.
ENERGY_DEFICIT_KCAL = 400
ENERGY_FLOOR_KCAL = {"male": 1500, "female": 1200}
# ASUMSI KIRA: bawaan bila umur/jenis kelamin belum diisi (AKG perempuan 30-49 tahun, nilai tengah dewasa).
ENERGY_DEFAULT_KCAL = 2150
# ASUMSI KIRA: pembagian energi dan batas harian per waktu makan.
MEAL_SPLIT = {"breakfast": 0.25, "lunch": 0.35, "dinner": 0.30, "snack": 0.10}
# Tidur: SUMBER (sekunder, konsensus): AASM/SRS (Watson dkk., J Clin Sleep Med 2015;11:591) dewasa 7 jam atau lebih;
# rentang 7-9 jam. Target 8 jam bila rata-rata terkini < 7: keputusan KIRA.
SLEEP_TARGET_RANGE = (7.0, 9.0)
SLEEP_CATCHUP_TARGET = 8.0
# Aktivitas: SUMBER (primer): WHO 2020 Guidelines on physical activity: dewasa 150-300 menit intensitas sedang per
# minggu dan penguatan otot >= 2 hari per minggu. ASUMSI KIRA: tanjakan untuk yang jauh di bawah target dimulai dari
# max(30, 1,2 x rata-rata mingguan 2 minggu terakhir) dan naik paling banyak 20% per minggu sampai 150.
EXERCISE_WEEKLY_TARGET = 150
EXERCISE_RAMP_MIN = 30
EXERCISE_RAMP_FACTOR = 1.2
