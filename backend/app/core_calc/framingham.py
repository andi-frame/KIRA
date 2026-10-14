"""Skor Framingham untuk insiden hipertensi (Parikh dkk., Ann Intern Med 2008;148:102-110).

Model regresi Weibull; koefisien dan intercept dibaca dari halaman resmi Framingham Heart Study
(https://www.framinghamheartstudy.org/fhs-for-researchers/fhs-risk-functions/hypertension/) dan satuan variabel
dikonfirmasi di Tehran Lipid and Glucose Study (PMC8070324): usia per tahun, TDS/TDD per mmHg, IMT per kg/m2.

Risiko t tahun = 1 - exp(-exp((ln t - mu) / sigma)), mu = intercept + sum(beta * x).

Batas pemakaian (kohort asal): usia 20-69, tanpa diabetes, belum hipertensi (TD < 140/90), dan populasi kulit putih
Framingham. Belum divalidasi untuk populasi Indonesia: aplikasi harus menyebut ini.
"""
import math
from dataclasses import dataclass
from itertools import product

INTERCEPT = 22.94954
SCALE = 0.87692
HORIZON_YEARS = 4
BETA = {
    "age": -0.15641,
    "female": -0.20293,
    "sbp": -0.05933,
    "dbp": -0.12847,
    "smoker": -0.19073,
    "parental": -0.16612,  # jumlah orang tua dengan hipertensi: 0, 1, atau 2
    "bmi": -0.03388,
    "age_x_dbp": 0.00162,
}
# Kategori risiko 4 tahun dari makalah: rendah < 5%, sedang 5-10%, tinggi > 10%.
LOW_BELOW = 0.05
HIGH_ABOVE = 0.10


@dataclass(frozen=True)
class FraminghamInputs:
    age: int
    female: bool
    sbp: int
    dbp: int
    smoker: bool
    parental: int
    bmi: float


def risk_4y(i: FraminghamInputs) -> float:
    mu = (
        INTERCEPT
        + BETA["age"] * i.age
        + BETA["female"] * (1 if i.female else 0)
        + BETA["sbp"] * i.sbp
        + BETA["dbp"] * i.dbp
        + BETA["smoker"] * (1 if i.smoker else 0)
        + BETA["parental"] * i.parental
        + BETA["bmi"] * i.bmi
        + BETA["age_x_dbp"] * i.age * i.dbp
    )
    return 1 - math.exp(-math.exp((math.log(HORIZON_YEARS) - mu) / SCALE))


def category(risk: float) -> str:
    if risk < LOW_BELOW:
        return "low"
    return "medium" if risk <= HIGH_ABOVE else "high"


def risk_range(
    *,
    age: int,
    female: bool,
    sbp: int,
    dbp: int,
    bmi: float,
    smoker: bool | None,
    parental_options: tuple[int, ...],
) -> tuple[float, float]:
    """Rentang risiko bila merokok atau riwayat orang tua belum diketahui (semua kemungkinan dihitung)."""
    smoker_options = (False, True) if smoker is None else (smoker,)
    values = [
        risk_4y(FraminghamInputs(age, female, sbp, dbp, s, p, bmi))
        for s, p in product(smoker_options, parental_options)
    ]
    return min(values), max(values)


def eligibility(*, age: int, sbp: int, dbp: int, has_diabetes: bool) -> str | None:
    """None bila model boleh dipakai; selain itu alasan mengapa tidak."""
    if has_diabetes:
        return "has_diabetes"
    if not 20 <= age <= 69:
        return "out_of_age_range"
    if sbp >= 140 or dbp >= 90:
        return "already_hypertensive"
    return None
