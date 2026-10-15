"""Rata-rata tekanan darah di rumah (HBPM) menurut protokol ESH 2021. Fungsi murni.

Protokol (Stergiou dkk., 2021 ESH Practice Guidelines, J Hypertens 39:1293-1302, Box 6 dan 7):
ukur 7 hari (minimal 3 hari), pagi dan malam, dua kali tiap sesi berjarak 1 menit. Saat menilai: buang hari pertama,
rata-ratakan semua bacaan sisanya; rata-rata >= 135/85 mmHg menandakan rentang hipertensi.

Hasilnya penanda untuk dokter, bukan diagnosis.
"""
from dataclasses import dataclass
from datetime import date, datetime

from app.core_calc.constants import HBPM_HOME_THRESHOLD, HBPM_MIN_DAYS, HBPM_MIN_READINGS, HBPM_PROTOCOL_DAYS
from app.timeutil import local_date

SESSIONS = ("morning", "evening")


@dataclass(frozen=True)
class Reading:
    at: datetime
    sys: int
    dia: int
    session: str  # morning | evening


@dataclass(frozen=True)
class DayCount:
    day: date
    morning: int
    evening: int
    discarded: bool  # hari pertama: dicatat tetapi tidak ikut rata-rata


@dataclass(frozen=True)
class HbpmSummary:
    days: list[DayCount]
    readings_used: int
    days_used: int
    avg_sys: float | None  # None bila belum cukup untuk dinilai
    avg_dia: float | None
    valid: bool
    range: str | None  # hypertension_range | below_threshold | None
    missing: str | None  # penjelasan apa yang masih kurang


def validate_reading(sys: int, dia: int) -> None:
    from app.core_calc.bp import bp_category

    bp_category(sys, dia)  # ValueError bila tidak masuk akal


def summarize(readings: list[Reading]) -> HbpmSummary:
    """Ringkasan protokol dari bacaan yang ada. Hari pertama (menurut tanggal lokal bacaan paling awal) dibuang."""
    if not readings:
        return HbpmSummary([], 0, 0, None, None, False, None, _missing(0, 0))
    ordered = sorted(readings, key=lambda r: r.at)
    first_day = local_date(ordered[0].at)
    by_day: dict[date, list[Reading]] = {}
    for r in ordered:
        by_day.setdefault(local_date(r.at), []).append(r)
    days = [
        DayCount(
            day=d,
            morning=sum(1 for r in rs if r.session == "morning"),
            evening=sum(1 for r in rs if r.session == "evening"),
            discarded=d == first_day,
        )
        for d, rs in sorted(by_day.items())
    ]
    used = [r for d, rs in by_day.items() if d != first_day for r in rs]
    days_used = len({local_date(r.at) for r in used})
    valid = days_used >= HBPM_MIN_DAYS and len(used) >= HBPM_MIN_READINGS
    if not valid:
        return HbpmSummary(days, len(used), days_used, None, None, False, None, _missing(len(used), days_used))
    avg_sys = round(sum(r.sys for r in used) / len(used), 1)
    avg_dia = round(sum(r.dia for r in used) / len(used), 1)
    high = avg_sys >= HBPM_HOME_THRESHOLD[0] or avg_dia >= HBPM_HOME_THRESHOLD[1]
    return HbpmSummary(
        days, len(used), days_used, avg_sys, avg_dia, True, "hypertension_range" if high else "below_threshold", None
    )


def _missing(readings_used: int, days_used: int) -> str:
    parts = []
    if days_used < HBPM_MIN_DAYS:
        parts.append(f"{HBPM_MIN_DAYS - days_used} hari lagi")
    if readings_used < HBPM_MIN_READINGS:
        parts.append(f"{HBPM_MIN_READINGS - readings_used} bacaan lagi")
    return (
        "Belum cukup untuk dihitung: butuh " + " dan ".join(parts) + f" (hari pertama dibuang; minimal {HBPM_MIN_DAYS} hari "
        f"dan {HBPM_MIN_READINGS} bacaan)."
    )


def protocol_day_index(started: date, today: date) -> int:
    """Hari ke berapa (1..7) dalam protokol; dibatasi pada HBPM_PROTOCOL_DAYS."""
    return max(1, min(HBPM_PROTOCOL_DAYS, (today - started).days + 1))
