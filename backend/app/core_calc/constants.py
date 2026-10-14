"""Konstanta klinis KIRA.

SEMUA nilai di sini SEMENTARA untuk development. Setiap blok bertanda TODO-VERIFY
dan wajib dicocokkan dengan sumber aslinya sebelum masuk materi submission.
"""

# TODO-VERIFY: Lindstrom & Tuomilehto, Diabetes Care 2003 + varian cut-off Asia (IMT, lingkar perut).
# Band = daftar (batas_atas_eksklusif, poin) berurutan; nilai di atas band terakhir mendapat "top".
# Batas IMT/lingkar perut memakai +0.05 agar nilai tepat di batas atas masuk band bawah
# (IMT dan lingkar perut dibulatkan 1 desimal).
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

# TODO-VERIFY: kategori skor FINDRISC (lo, hi, label), total 0-26.
FINDRISC_CATEGORIES = [
    (0, 6, "low"),
    (7, 11, "slightly_elevated"),
    (12, 14, "moderate"),
    (15, 20, "high"),
    (21, 26, "very_high"),
]

# TODO-VERIFY: insidensi diabetes 10 tahun per kategori (paper validasi FINDRISC). Nilai sementara.
P10_BY_CATEGORY = {
    "low": 0.01,
    "slightly_elevated": 0.04,
    "moderate": 0.17,
    "high": 0.33,
    "very_high": 0.50,
}

# TODO-VERIFY: ambang tekanan darah Kemenkes/CKG. (sistolik, diastolik) minimum untuk tiap kategori.
BP_THRESHOLDS = {
    "hypertension": (140, 90),
    "prehypertension": (120, 80),
}

# TODO-VERIFY: ambang tanda bahaya dari pedoman resmi.
RED_FLAG_BP = (180, 120)  # (sistolik, diastolik): salah satu terpenuhi
RED_FLAG_GLUCOSE = {"high": 300, "low": 70}  # mg/dL
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

# TODO-VERIFY: ambang gula darah yang dianggap "pernah tinggi" untuk faktor FINDRISC (mg/dL).
GLUCOSE_HIGH_FASTING = 100
GLUCOSE_HIGH_RANDOM = 140
GLUCOSE_HIGH_HBA1C = 5.7  # persen, TODO-VERIFY (batas prediabetes)

# TODO-VERIFY: batas konsumsi harian Kemenkes.
DAILY_LIMITS = {"sugar_g": 50.0, "sodium_mg": 2000.0, "fat_g": 67.0}

# TODO-VERIFY: pengali batas untuk mode pengelolaan (lebih ketat), arahkan ke ahli gizi/dokter.
MANAGEMENT_STRICTNESS = 0.8
