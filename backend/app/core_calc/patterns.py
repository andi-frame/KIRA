"""Pola deskriptif dari catatan pengguna sendiri: apakah hari dengan tidur pendek berbeda dari hari lain?

Hanya membandingkan rata-rata dua kelompok hari. Bukan sebab-akibat, bukan uji statistik: dengan data sedikit selisih
bisa kebetulan, jadi tiap kelompok butuh minimal MIN_PER_GROUP hari, dan hasilnya selalu disertai catatan itu.

Batas "tidur pendek" (< 6 jam) adalah keputusan KIRA yang mengikuti kategori yang lazim dipakai studi epidemiologi;
konsensus AASM/SRS (Watson dkk., J Clin Sleep Med 2015;11:591) menyarankan dewasa tidur 7 jam atau lebih.
"""
from dataclasses import dataclass

SHORT_SLEEP_HOURS = 6.0
MIN_PER_GROUP = 3

# (kunci di deret harian, label, satuan, desimal)
DAILY_METRICS = (
    ("sugar_g", "Gula dari makan dan minum", "g", 0),
    ("sweet_drinks", "Minuman manis", "gelas", 1),
    ("active_minutes", "Menit aktif", "menit", 0),
)


@dataclass(frozen=True)
class Comparison:
    key: str
    label: str
    unit: str
    short_avg: float
    other_avg: float
    n_short: int
    n_other: int

    @property
    def diff(self) -> float:
        return self.short_avg - self.other_avg


def _avg(values: list[float]) -> float:
    return sum(values) / len(values)


def compare_metric(key: str, label: str, unit: str, short: list[float], other: list[float], digits: int = 0) -> Comparison | None:
    """None bila salah satu kelompok kurang dari MIN_PER_GROUP: lebih baik diam daripada menyimpulkan dari satu-dua hari."""
    if len(short) < MIN_PER_GROUP or len(other) < MIN_PER_GROUP:
        return None
    return Comparison(key, label, unit, round(_avg(short), digits), round(_avg(other), digits), len(short), len(other))


def compare_by_sleep(days: list[dict], clinical_by_day: dict[str, list[float]] | None = None) -> dict:
    """Bandingkan hari tidur pendek (< 6 jam) dengan hari lain pada hari yang sama.

    days: deret harian (date, sleep_hours, sugar_g, sweet_drinks, active_minutes); hari tanpa catatan tidur tidak ikut.
    clinical_by_day: tanggal -> sistolik yang diukur hari itu (opsional).
    """
    with_sleep = [d for d in days if d.get("sleep_hours") is not None]
    short_days = [d for d in with_sleep if d["sleep_hours"] < SHORT_SLEEP_HOURS]
    other_days = [d for d in with_sleep if d["sleep_hours"] >= SHORT_SLEEP_HOURS]

    comparisons: list[Comparison] = []
    for key, label, unit, digits in DAILY_METRICS:
        short = [float(d[key]) for d in short_days if d.get(key) is not None]
        other = [float(d[key]) for d in other_days if d.get(key) is not None]
        c = compare_metric(key, label, unit, short, other, digits)
        if c:
            comparisons.append(c)

    if clinical_by_day:
        short_dates = {d["date"] for d in short_days}
        other_dates = {d["date"] for d in other_days}
        short = [v for day, vs in clinical_by_day.items() if day in short_dates for v in vs]
        other = [v for day, vs in clinical_by_day.items() if day in other_dates for v in vs]
        c = compare_metric("systolic", "Tekanan darah atas (sistolik)", "mmHg", short, other, 0)
        if c:
            comparisons.append(c)

    return {
        "threshold_hours": SHORT_SLEEP_HOURS,
        "short_days": len(short_days),
        "other_days": len(other_days),
        "min_per_group": MIN_PER_GROUP,
        "comparisons": comparisons,
        "needs_more_data": not comparisons,
    }
