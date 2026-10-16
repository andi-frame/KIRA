"""Penanda untuk membantu dokter memprioritaskan (triase): murni aturan, tanpa LLM.

Semua kata-katanya menandai pembacaan terhadap ambang pedoman, bukan menetapkan diagnosis.
Ambang: BP (KMK 303/2026), glukosa dan HbA1c (PERKENI 2021); lihat constants.py.
"""
from app.core_calc.bp import bp_category
from app.core_calc.heart_rate import RESTING_HIGH, RESTING_LOW, classify_resting
from app.core_calc.constants import (
    BP_THRESHOLDS,
    GLUCOSE_DIABETES_FASTING,
    GLUCOSE_HIGH_FASTING,
    GLUCOSE_HIGH_HBA1C,
    GLUCOSE_HIGH_RANDOM,
    HBA1C_DIABETES,
    HBPM_HOME_THRESHOLD,
    TREND_NOISE,
)

NOT_DIAGNOSIS = "Satu pembacaan bukan diagnosis; perlu konfirmasi dan penilaian dokter."


def glucose_range(kind: str, mg_dl: float) -> str:
    """normal | prediabetes | diabetes_range (puasa); below_cutoff | diabetes_range (sewaktu)."""
    if kind == "random_glucose":
        return "diabetes_range" if mg_dl >= GLUCOSE_HIGH_RANDOM else "below_cutoff"
    if mg_dl >= GLUCOSE_DIABETES_FASTING:
        return "diabetes_range"
    return "prediabetes" if mg_dl >= GLUCOSE_HIGH_FASTING else "normal"


def hba1c_range(pct: float) -> str:
    if pct >= HBA1C_DIABETES:
        return "diabetes_range"
    return "prediabetes" if pct >= GLUCOSE_HIGH_HBA1C else "normal"


def trend_label(kind: str, values: list[float]) -> str | None:
    """naik | turun | stabil dari pengukuran pertama ke terakhir; None bila kurang dari dua titik."""
    if len(values) < 2:
        return None
    delta = values[-1] - values[0]
    if abs(delta) < TREND_NOISE.get(kind, 0.0):
        return "stabil"
    return "naik" if delta > 0 else "turun"


def _flag(level: str, kind: str, text: str) -> dict:
    return {"level": level, "kind": kind, "text": text}


def triage_flags(latest: dict, diabetes_category_high: str | None) -> list[dict]:
    """Penanda dari hasil pemeriksaan terakhir tiap jenis. level: perhatian | pantau | info (diurutkan begitu)."""
    flags: list[dict] = []
    home = latest.get("home_bp_average")  # (sistolik, diastolik, jumlah bacaan) dari protokol 7 hari
    if home is not None:
        sys_avg, dia_avg, n = home
        t = HBPM_HOME_THRESHOLD
        if sys_avg >= t[0] or dia_avg >= t[1]:
            flags.append(_flag("perhatian", "blood_pressure",
                               f"Rata-rata tensi di rumah {sys_avg:g}/{dia_avg:g} mmHg ({n} bacaan, 7 hari) berada di rentang hipertensi "
                               f"(>={t[0]}/{t[1]} untuk tensi rumah, ESH 2021). Rata-rata beberapa hari lebih dapat dipercaya daripada satu "
                               "bacaan, tetapi tetap perlu konfirmasi dan penilaian dokter."))
    bp = latest.get("blood_pressure")
    if bp is not None:
        sys, dia = bp
        category = bp_category(int(sys), int(dia))
        if category == "hypertension":
            h = BP_THRESHOLDS["hypertension"]
            flags.append(_flag("perhatian", "blood_pressure",
                               f"Tekanan darah terakhir {sys}/{dia} mmHg berada di rentang hipertensi (>={h[0]}/{h[1]}, KMK 303/2026). {NOT_DIAGNOSIS}"))
        elif category == "prehypertension":
            flags.append(_flag("pantau", "blood_pressure",
                               f"Tekanan darah terakhir {sys}/{dia} mmHg berada di rentang normal-tinggi (130-139/85-89): pantau dan ukur ulang."))
    bpm = latest.get("resting_heart_rate")
    if bpm is not None:
        rng = classify_resting(bpm)
        if rng == "above_range":
            flags.append(_flag("pantau", "resting_heart_rate",
                               f"Detak jantung istirahat terakhir {bpm:g} kali/menit, di atas {RESTING_HIGH} (rentang normal dewasa "
                               f"{RESTING_LOW}-{RESTING_HIGH}, AHA). Ukur ulang setelah duduk tenang 5 menit; bila tetap tinggi, "
                               "bicarakan dengan dokter. Kafein, kurang tidur, demam, dan stres bisa menaikkannya."))
        elif rng == "below_range":
            flags.append(_flag("info", "resting_heart_rate",
                               f"Detak jantung istirahat terakhir {bpm:g} kali/menit, di bawah {RESTING_LOW}. Ini sering wajar pada "
                               "orang yang rutin berolahraga; bila bukan, atau disertai pusing atau pingsan, bicarakan dengan dokter."))
    for kind, label in (("fasting_glucose", "Gula darah puasa"), ("random_glucose", "Gula darah sewaktu")):
        mg = latest.get(kind)
        if mg is None:
            continue
        rng = glucose_range(kind, mg)
        if rng == "diabetes_range":
            cutoff = GLUCOSE_DIABETES_FASTING if kind == "fasting_glucose" else GLUCOSE_HIGH_RANDOM
            flags.append(_flag("perhatian", kind, f"{label} terakhir {mg:g} mg/dL berada di rentang diabetes (>={cutoff}, PERKENI 2021). {NOT_DIAGNOSIS}"))
        elif rng == "prediabetes":
            flags.append(_flag("pantau", kind, f"{label} terakhir {mg:g} mg/dL berada di rentang prediabetes (100-125, PERKENI 2021): pantau."))
    pct = latest.get("hba1c")
    if pct is not None:
        rng = hba1c_range(pct)
        if rng == "diabetes_range":
            flags.append(_flag("perhatian", "hba1c", f"HbA1c terakhir {pct:g}% berada di rentang diabetes (>=6,5%, PERKENI 2021). {NOT_DIAGNOSIS}"))
        elif rng == "prediabetes":
            flags.append(_flag("pantau", "hba1c", f"HbA1c terakhir {pct:g}% berada di rentang prediabetes (5,7-6,4%, PERKENI 2021): pantau."))
    if diabetes_category_high in {"high", "very_high"}:
        flags.append(_flag("pantau", "findrisc", "Skrining FINDRISC (perkiraan 10 tahun) berada di kategori tinggi pada batas atas rentang: pertimbangkan pemeriksaan gula darah."))
    if not any(latest.get(k) is not None for k in ("blood_pressure", "home_bp_average", "fasting_glucose", "random_glucose", "hba1c")):
        flags.append(_flag("info", "no_results", "Belum ada hasil pemeriksaan yang dicatat di KIRA; proyeksi memakai perkiraan dari kebiasaan."))
    order = {"perhatian": 0, "pantau": 1, "info": 2}
    return sorted(flags, key=lambda f: order[f["level"]])
