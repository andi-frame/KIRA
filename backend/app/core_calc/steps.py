"""Menit aktif dari catatan langkah (mis. Health Connect), tanpa memakai tebakan model.

Aturan: segmen waktu dengan kadensi rata-rata >= 100 langkah/menit dihitung sebagai jalan intensitas sedang.
Ambang 100 langkah/menit adalah nilai heuristik untuk intensitas sedang (3 MET) pada orang dewasa usia 21-40 tahun
(Tudor-Locke dkk., Int J Behav Nutr Phys Act 2019;16:8). Segmen yang lebih panjang dari satu menit dirata-ratakan,
jadi jalan santai yang panjang tidak dihitung: hasilnya cenderung konservatif. Pemakaian untuk usia lain adalah
perkiraan KIRA.
"""
from collections import defaultdict
from dataclasses import dataclass
from datetime import date, datetime

from app.timeutil import local_date

MODERATE_CADENCE = 100  # langkah/menit
MAX_PLAUSIBLE_CADENCE = 250  # di atas ini hampir pasti galat sensor/duplikasi


@dataclass(frozen=True)
class StepSegment:
    start: datetime
    end: datetime
    steps: int

    @property
    def minutes(self) -> float:
        return (self.end - self.start).total_seconds() / 60


def _plausible(s: StepSegment) -> bool:
    """Durasi positif, langkah tidak negatif, kadensi masuk akal."""
    minutes = s.minutes
    return minutes > 0 and s.steps >= 0 and s.steps / minutes <= MAX_PLAUSIBLE_CADENCE


def moderate_minutes_by_day(segments: list[StepSegment]) -> dict[date, float]:
    """Menit jalan intensitas sedang per hari (WIB). Hari yang punya langkah tetapi tanpa menit sedang bernilai 0,
    supaya hari tidak aktif ikut dihitung. Segmen tidak wajar (durasi <= 0, langkah negatif, kadensi mustahil) dibuang."""
    days: dict[date, float] = defaultdict(float)
    for s in segments:
        if not _plausible(s):
            continue
        days[local_date(s.start)] += s.minutes if s.steps / s.minutes >= MODERATE_CADENCE else 0.0
    return dict(days)


def steps_by_day(segments: list[StepSegment]) -> dict[date, int]:
    """Total langkah per hari (WIB) dari segmen yang wajar."""
    days: dict[date, int] = defaultdict(int)
    for s in segments:
        if _plausible(s):
            days[local_date(s.start)] += s.steps
    return dict(days)
