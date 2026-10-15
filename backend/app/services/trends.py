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
from app.core_calc.triage import glucose_range, hba1c_range, trend_label, triage_flags
from app.models import ClinicalResult, Log, LogItem
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
}


def _point(kind: str, r: ClinicalResult) -> dict:
    base = {"date": local_date(r.measured_at).isoformat(), "measured_at": r.measured_at.isoformat(), "source": r.source}
    v = r.value
    if kind == "blood_pressure":
        sys, dia = int(v["sys"]), int(v["dia"])
        return {**base, "sys": sys, "dia": dia, "category": bp_category(sys, dia)}
    if kind in ("fasting_glucose", "random_glucose"):
        return {**base, "value": v["mg_dl"], "range": glucose_range(kind, v["mg_dl"])}
    if kind == "hba1c":
        return {**base, "value": v["percent"], "range": hba1c_range(v["percent"])}
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
    if bp:
        latest["blood_pressure"] = (bp["sys"], bp["dia"])
    for kind in ("fasting_glucose", "random_glucose", "hba1c"):
        point = clinical[kind]["latest"]
        if point:
            latest[kind] = point["value"]
    return latest


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
