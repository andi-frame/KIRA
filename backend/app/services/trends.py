"""Deret waktu untuk grafik tren (hasil pemeriksaan dan kebiasaan harian) dan penanda triase.

Dipakai bersama oleh layar tren di aplikasi, ringkasan untuk dokter, dan PDF-nya, supaya angkanya selalu sama.
"""
import uuid
from collections import defaultdict
from datetime import date, datetime, time, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.bp import bp_category
from app.core_calc.constants import (
    BP_THRESHOLDS,
    DAILY_LIMITS,
    GLUCOSE_DIABETES_FASTING,
    GLUCOSE_HIGH_FASTING,
    GLUCOSE_HIGH_HBA1C,
    GLUCOSE_HIGH_RANDOM,
    HBA1C_DIABETES,
)
from app.core_calc.constants import FINDRISC_CATEGORIES
from app.core_calc.heart_rate import RESTING_HIGH, RESTING_LOW, classify_resting
from app.core_calc.patterns import SHORT_SLEEP_HOURS, compare_by_sleep
from app.core_calc.triage import glucose_range, hba1c_range, trend_label, triage_flags
from app.models import ClinicalResult, Log, LogItem, RiskSnapshot
from app.services import risk
from app.timeutil import WIB, local_date, utcnow

CLINICAL_DAYS = 180
ACTIVE_MINUTES_TARGET = risk.ACTIVE_MINUTES_PER_DAY

REFERENCES = {
    "blood_pressure": [
        {"label": "Hipertensi (sistolik)", "value": BP_THRESHOLDS["hypertension"][0]},
        {"label": "Hipertensi (diastolik)", "value": BP_THRESHOLDS["hypertension"][1]},
        {"label": "Normal-tinggi (sistolik)", "value": BP_THRESHOLDS["prehypertension"][0]},
        {"label": "Normal-tinggi (diastolik)", "value": BP_THRESHOLDS["prehypertension"][1]},
    ],
    "fasting_glucose": [
        {"label": "Prediabetes mulai", "value": GLUCOSE_HIGH_FASTING},
        {"label": "Rentang diabetes mulai", "value": GLUCOSE_DIABETES_FASTING},
    ],
    "random_glucose": [{"label": "Rentang diabetes mulai", "value": GLUCOSE_HIGH_RANDOM}],
    "hba1c": [
        {"label": "Prediabetes mulai", "value": GLUCOSE_HIGH_HBA1C},
        {"label": "Rentang diabetes mulai", "value": HBA1C_DIABETES},
    ],
    "waist": [],
    "resting_heart_rate": [
        {"label": "Batas bawah normal istirahat", "value": RESTING_LOW},
        {"label": "Batas atas normal istirahat", "value": RESTING_HIGH},
    ],
}


def _point(kind: str, r: ClinicalResult) -> dict:
    base = {"date": local_date(r.measured_at).isoformat(), "measured_at": r.measured_at.isoformat(), "source": r.source}
    v = r.value
    if kind == "blood_pressure":
        sys, dia = int(v["sys"]), int(v["dia"])
        point = {**base, "sys": sys, "dia": dia, "category": bp_category(sys, dia)}
        if v.get("protocol"):  # rata-rata protokol 7 hari di rumah, bukan satu bacaan
            point.update(home_average=True, readings=v.get("readings"), avg_sys=v.get("avg_sys"), avg_dia=v.get("avg_dia"))
        return point
    if kind in ("fasting_glucose", "random_glucose"):
        return {**base, "value": v["mg_dl"], "range": glucose_range(kind, v["mg_dl"])}
    if kind == "hba1c":
        return {**base, "value": v["percent"], "range": hba1c_range(v["percent"])}
    if kind == "resting_heart_rate":
        return {**base, "value": v["bpm"], "range": classify_resting(v["bpm"])}
    return {**base, "value": v.get("cm")}


async def clinical_trends(session: AsyncSession, user_id: uuid.UUID, days: int = CLINICAL_DAYS) -> dict:
    cutoff = utcnow() - timedelta(days=days)
    rows = (
        await session.execute(
            select(ClinicalResult)
            .where(ClinicalResult.user_id == user_id, ClinicalResult.measured_at >= cutoff)
            .order_by(ClinicalResult.measured_at)
        )
    ).scalars().all()
    out: dict[str, dict] = {}
    for kind, refs in REFERENCES.items():
        points = []
        for r in rows:
            if r.kind != kind:
                continue
            try:
                points.append(_point(kind, r))
            except (KeyError, ValueError, TypeError):
                continue  # baris rusak tidak boleh menjatuhkan seluruh grafik
        series = [p["sys"] if kind == "blood_pressure" else p["value"] for p in points]
        out[kind] = {
            "points": points,
            "latest": points[-1] if points else None,
            "count": len(points),
            "trend": trend_label("sys" if kind == "blood_pressure" else kind, [float(s) for s in series]),
            "references": refs,
        }
    return out


async def daily_series(session: AsyncSession, user_id: uuid.UUID, start: date, end: date) -> list[dict]:
    lo = datetime.combine(start, time.min, tzinfo=WIB)
    hi = datetime.combine(end + timedelta(days=1), time.min, tzinfo=WIB)
    logs = (
        await session.execute(select(Log).where(Log.user_id == user_id, Log.occurred_at >= lo, Log.occurred_at < hi))
    ).scalars().all()
    items = (
        await session.execute(select(LogItem).where(LogItem.log_id.in_([lg.id for lg in logs]))) if logs else None
    )
    by_log: dict[uuid.UUID, list[LogItem]] = defaultdict(list)
    for item in (items.scalars().all() if items else []):
        by_log[item.log_id].append(item)

    days: dict[date, dict] = {}
    for lg in logs:
        d = days.setdefault(local_date(lg.occurred_at), {"sugar": 0.0, "sweet": 0.0, "sleep": [], "active": 0.0})
        sugar = sum(float(i.sugar_g or 0) for i in by_log[lg.id])
        d["sugar"] += sugar
        if lg.kind == "drink":
            count = float(lg.extracted.get("count", 1) or 1)
            if sugar / count >= risk.SWEET_DRINK_MIN_SUGAR_G:
                d["sweet"] += count
        elif lg.kind == "sleep" and lg.extracted.get("hours"):
            d["sleep"].append(float(lg.extracted["hours"]))
        elif lg.kind == "activity":
            d["active"] += float(lg.extracted.get("minutes", 0) or 0)

    series = []
    for offset in range((end - start).days + 1):
        day = start + timedelta(days=offset)
        d = days.get(day)
        series.append({
            "date": day.isoformat(),
            "logged": d is not None,
            "sugar_g": round(d["sugar"], 1) if d else None,
            "sweet_drinks": round(d["sweet"], 1) if d else None,
            "sleep_hours": round(max(d["sleep"]), 1) if d and d["sleep"] else None,
            "active_minutes": round(d["active"], 1) if d else None,
        })
    return series


def latest_for_triage(clinical: dict) -> dict:
    latest: dict = {}
    bp = clinical["blood_pressure"]["latest"]
    if bp and bp.get("home_average"):
        latest["home_bp_average"] = (bp.get("avg_sys") or bp["sys"], bp.get("avg_dia") or bp["dia"], bp.get("readings") or 0)
    elif bp:
        latest["blood_pressure"] = (bp["sys"], bp["dia"])
    for kind in ("fasting_glucose", "random_glucose", "hba1c", "resting_heart_rate"):
        point = clinical[kind]["latest"]
        if point:
            latest[kind] = point["value"]
    return latest


PATTERN_DISCLAIMER = (
    "Ini pola dari catatanmu sendiri, bukan sebab pasti. Selisih bisa kebetulan, terutama kalau datanya baru sedikit. "
    "Bahas bersama dokter sebelum mengambil kesimpulan."
)


async def sleep_patterns(session: AsyncSession, user_id: uuid.UUID, days: int) -> dict:
    """Bandingkan hari tidur pendek dengan hari lain (gula, minuman manis, menit aktif, dan sistolik di hari yang sama)."""
    today = local_date(utcnow())
    series = await daily_series(session, user_id, today - timedelta(days=days - 1), today)
    cutoff = utcnow() - timedelta(days=days)
    bp_rows = (
        await session.execute(
            select(ClinicalResult).where(
                ClinicalResult.user_id == user_id, ClinicalResult.kind == "blood_pressure", ClinicalResult.measured_at >= cutoff
            )
        )
    ).scalars().all()
    by_day: dict[str, list[float]] = defaultdict(list)
    for r in bp_rows:
        if r.value.get("protocol"):
            continue  # rata-rata protokol mewakili beberapa hari, bukan satu hari
        try:
            by_day[local_date(r.measured_at).isoformat()].append(float(r.value["sys"]))
        except (KeyError, TypeError, ValueError):
            continue
    result = compare_by_sleep(series, dict(by_day))
    return {
        "period_days": days,
        "sleep": {
            "threshold_hours": result["threshold_hours"],
            "short_days": result["short_days"],
            "other_days": result["other_days"],
            "min_per_group": result["min_per_group"],
            "needs_more_data": result["needs_more_data"],
            "comparisons": [
                {"key": c.key, "label": c.label, "unit": c.unit, "short_avg": c.short_avg, "other_avg": c.other_avg,
                 "diff": round(c.diff, 1), "n_short": c.n_short, "n_other": c.n_other}
                for c in result["comparisons"]
            ],
        },
        "disclaimer": PATTERN_DISCLAIMER,
    }


async def risk_history(session: AsyncSession, user_id: uuid.UUID, days: int) -> dict:
    """Skor FINDRISC dari waktu ke waktu (satu titik per hari: yang terakhir), beserta batas kategori."""
    cutoff = utcnow() - timedelta(days=days)
    rows = (
        await session.execute(
            select(RiskSnapshot)
            .where(RiskSnapshot.user_id == user_id, RiskSnapshot.model == "findrisc", RiskSnapshot.computed_at >= cutoff)
            .order_by(RiskSnapshot.computed_at)
        )
    ).scalars().all()
    per_day: dict[date, RiskSnapshot] = {}
    for r in rows:
        if r.score_low is not None and r.score_high is not None:
            per_day[local_date(r.computed_at)] = r  # yang terakhir pada hari itu menimpa
    points = [
        {"date": d.isoformat(), "score_low": r.score_low, "score_high": r.score_high,
         "category_low": r.category_low, "category_high": r.category_high}
        for d, r in sorted(per_day.items())
    ]
    return {
        "period_days": days,
        "points": points,
        "categories": [{"min": lo, "max": hi, "category": cat} for lo, hi, cat in FINDRISC_CATEGORIES],
        "note": "Rentang melebar saat data profil atau hasil cek belum ada, dan menyempit seiring data nyata masuk.",
    }


async def build_trends(session: AsyncSession, user_id: uuid.UUID, days: int) -> dict:
    today = local_date(utcnow())
    clinical = await clinical_trends(session, user_id)
    state = await risk.compute_risk_state(session, user_id)
    return {
        "period_days": days,
        "clinical": clinical,
        "daily": await daily_series(session, user_id, today - timedelta(days=days - 1), today),
        "references": {"sugar_g": DAILY_LIMITS["sugar_g"], "active_minutes": ACTIVE_MINUTES_TARGET},
        # Profil belum lengkap membuat rentang FINDRISC sangat lebar: jangan jadikan penanda.
        "triage": triage_flags(latest_for_triage(clinical), None if state.needs_profile else state.category_high),
    }
