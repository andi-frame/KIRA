"""Ringkasan untuk dokter dan wawasan korelasi makanan vs gula darah."""
import uuid
from collections import defaultdict
from datetime import timedelta

from fastapi import APIRouter, Depends, Query, Response
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.models import ClinicalResult, Log, LogItem, User, WeeklySummary
from app.repos import profiles
from app.security import current_user_id
from app.services import risk
from app.services.jobs import _metrics, _summary_text, week_bounds, weekly_changes
from app.services.projection_view import hypertension_payload
from app.services.doctor_pdf import build_doctor_pdf
from app.services.trends import build_trends
from app.timeutil import local_date, utcnow

router = APIRouter(tags=["summary"])

MIN_SAMPLES = 3
MEAL_WINDOW = timedelta(hours=3)
CATEGORY_ID = {
    "low": "rendah", "slightly_elevated": "sedikit meningkat", "moderate": "sedang",
    "high": "tinggi", "very_high": "sangat tinggi",
}
KIND_ID = {
    "fasting_glucose": "Gula darah puasa", "random_glucose": "Gula darah sewaktu",
    "blood_pressure": "Tekanan darah", "hba1c": "HbA1c", "waist": "Lingkar perut",
}


def _value_text(kind: str, value: dict) -> str:
    if kind == "blood_pressure" and value.get("protocol"):
        return f"{value.get('avg_sys', value.get('sys')):g}/{value.get('avg_dia', value.get('dia')):g} mmHg ({value.get('readings')} bacaan)"
    if kind == "blood_pressure":
        return f"{value.get('sys')}/{value.get('dia')} mmHg"
    unit = {"fasting_glucose": "mg/dL", "random_glucose": "mg/dL", "hba1c": "%", "waist": "cm"}.get(kind, "")
    number = next(iter(value.values()), "")
    return f"{number} {unit}".strip()


def _result_label(kind: str, value: dict) -> str:
    if kind == "blood_pressure" and value.get("protocol"):
        return "Tensi rata-rata di rumah (7 hari)"
    return KIND_ID.get(kind, kind)


def _render_text(s: dict) -> str:
    p, risk_d, habits = s["patient"], s["risk"]["diabetes"], s["habits"]
    lines = [
        f"Ringkasan KIRA {s['period_days']} hari untuk {p['name']}"
        + (f" ({p['age']} tahun, {'laki-laki' if p['sex'] == 'male' else 'perempuan'})" if p["age"] else ""),
        "Dibuat otomatis dari catatan pengguna sendiri; bukan diagnosis dan bukan pengganti pemeriksaan.",
        "",
    ]
    if habits["days_logged"] == 0:
        lines.append("Kebiasaan: belum ada catatan pada periode ini.")
    else:
        lines.append(
            f"Kebiasaan ({habits['days_logged']} hari tercatat): gula dari makan dan minum rata-rata "
            f"{habits['sugar_g_per_day']:g} g/hari, minuman manis {habits['sweet_drinks_per_day']:g}/hari, "
            f"aktif {habits['active_minutes_per_day']:g} menit/hari"
            + (f", tidur rata-rata {habits['sleep_hours_avg']:g} jam." if habits["sleep_hours_avg"] else ".")
        )
    if s["top_foods"]:
        lines.append("Makanan yang paling sering dicatat: " + ", ".join(f"{f['name']} ({f['count']}x)" for f in s["top_foods"]) + ".")
    low, high = CATEGORY_ID.get(risk_d["category_low"], ""), CATEGORY_ID.get(risk_d["category_high"], "")
    lines.append(
        f"Skrining diabetes (FINDRISC, perkiraan 10 tahun): kategori {low}" + (f" sampai {high}" if high != low else "") + "."
    )
    flagged = [f for f in s["triage"] if f["level"] != "info"]
    if flagged:
        lines.append("Penanda untuk perhatian (aturan terhadap ambang pedoman, bukan diagnosis):")
        for f in flagged:
            lines.append(f"- [{'PERLU PERHATIAN' if f['level'] == 'perhatian' else 'PANTAU'}] {f['text']}")
    if s["clinical_results"]:
        lines.append("Hasil pemeriksaan yang dicatat:")
        for r in s["clinical_results"]:
            lines.append(f"- {r['label']}: {r['display']} ({r['measured_on']}, {r['source']})")
    else:
        lines.append("Belum ada hasil pemeriksaan yang dicatat di KIRA.")
    return "\n".join(lines)


async def compute_doctor_summary(session: AsyncSession, user_id: uuid.UUID, days: int, trends: dict) -> dict:
    today = local_date(utcnow())
    start = today - timedelta(days=days - 1)
    profile = await profiles.get(session, user_id)
    state = await risk.compute_risk_state(session, user_id)
    metrics = await _metrics(session, user_id, start, today) or {
        "days_logged": 0, "sweet_drinks_per_day": 0.0, "sugar_g_per_day": 0.0,
        "sleep_hours_avg": None, "active_minutes_per_day": 0.0,
    }
    cutoff = utcnow() - timedelta(days=days)
    top = (
        await session.execute(
            select(LogItem.name, func.count().label("n"))
            .join(Log, Log.id == LogItem.log_id)
            .where(Log.user_id == user_id, Log.kind == "meal", Log.occurred_at >= cutoff)
            .group_by(LogItem.name)
            .order_by(func.count().desc(), LogItem.name)
            .limit(8)
        )
    ).all()
    results = (
        await session.execute(
            select(ClinicalResult).where(ClinicalResult.user_id == user_id).order_by(ClinicalResult.measured_at.desc()).limit(10)
        )
    ).scalars().all()
    weekly = (
        await session.execute(
            select(WeeklySummary).where(WeeklySummary.user_id == user_id).order_by(WeeklySummary.week_start.desc()).limit(4)
        )
    ).scalars().all()
    user = await session.get(User, user_id)
    summary = {
        "generated_at": utcnow().isoformat(),
        "period_days": days,
        "patient": {
            "name": profile.display_name or "Pengguna KIRA", "age": profile.age, "sex": profile.sex,
            "height_cm": profile.height_cm,
            "weight_kg": profile.weight_kg, "family_history_diabetes": profile.family_history_diabetes,
        },
        "mode": user.mode if user else "prevention",
        "risk": {
            "diabetes": {
                "model": "FINDRISC",
                "score_low": state.rng.low, "score_high": state.rng.high,
                "category_low": state.category_low, "category_high": state.category_high,
            },
            "hypertension": hypertension_payload(state),
        },
        "habits": metrics,
        "top_foods": [{"name": n, "count": c} for n, c in top],
        "clinical_results": [
            {
                "kind": r.kind, "label": _result_label(r.kind, r.value), "value": r.value,
                "display": _value_text(r.kind, r.value), "measured_on": local_date(r.measured_at).isoformat(),
                "source": {"ckg": "CKG", "lab": "laboratorium", "self": "ukur sendiri"}.get(r.source, r.source),
            }
            for r in results
        ],
        "weekly_summaries": [w.summary_text for w in weekly if w.summary_text],
        "triage": trends["triage"],
    }
    summary["text"] = _render_text(summary)
    return summary


@router.get("/summary/doctor")
async def doctor_summary(
    days: int = Query(default=30, ge=1, le=90),
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    return await compute_doctor_summary(session, user_id, days, await build_trends(session, user_id, days))


@router.get("/insights/food-glucose")
async def food_glucose(
    user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    """Untuk pengguna dengan glukometer: rata-rata gula darah sewaktu setelah makanan tertentu (1-3 jam sesudahnya).

    Hanya korelasi dari catatan sendiri; makanan baru ditampilkan setelah minimal 3 pasangan data.
    """
    readings = (
        await session.execute(
            select(ClinicalResult).where(ClinicalResult.user_id == user_id, ClinicalResult.kind == "random_glucose")
        )
    ).scalars().all()
    by_food: dict[str, list[float]] = defaultdict(list)
    for reading in readings:
        mg = float(reading.value.get("mg_dl", 0))
        meals = (
            await session.execute(
                select(Log)
                .where(Log.user_id == user_id, Log.kind == "meal",
                       Log.occurred_at <= reading.measured_at, Log.occurred_at >= reading.measured_at - MEAL_WINDOW)
            )
        ).scalars().all()
        names: set[str] = set()
        for meal in meals:
            for item in (meal.extracted.get("items") or []):
                names.add(str(item.get("name", "")).lower())
        for name in names - {""}:
            by_food[name].append(mg)
    foods = sorted(
        (
            {"name": n, "samples": len(v), "avg_mg_dl": round(sum(v) / len(v))}
            for n, v in by_food.items() if len(v) >= MIN_SAMPLES
        ),
        key=lambda f: -f["avg_mg_dl"],
    )
    return {
        "foods": foods,
        "total_readings": len(readings),
        "needs_more_data": not foods,
        "disclaimer": "Ini pola dari catatanmu sendiri, bukan sebab pasti. Pembahasan hasilnya sebaiknya bersama dokter.",
    }



@router.get("/summary/weekly")
async def weekly_recap(
    user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    """Rekap minggu lalu (Senin-Minggu) beserta perubahan dari minggu sebelumnya. Dihitung langsung dari catatan,
    jadi tidak bergantung pada penjadwal sudah jalan atau belum."""
    start, end = week_bounds(local_date(utcnow()))
    metrics = await _metrics(session, user_id, start, end)
    if metrics is None:
        return {"week": None}
    prev = await _metrics(session, user_id, start - timedelta(days=7), start - timedelta(days=1))
    return {
        "week": {
            "start": start.isoformat(), "end": end.isoformat(), "metrics": metrics,
            "text": _summary_text(start, end, metrics), "changes": weekly_changes(metrics, prev),
        }
    }


@router.get("/insights/trends")
async def trends(
    days: int = Query(default=30, ge=1, le=90),
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Grafik tren: hasil pemeriksaan (180 hari), kebiasaan harian (`days`), dan penanda triase untuk dokter."""
    return await build_trends(session, user_id, days)


@router.get("/summary/doctor.pdf")
async def doctor_summary_pdf(
    days: int = Query(default=30, ge=1, le=90),
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> Response:
    """PDF satu sampai tiga halaman untuk dibawa atau dikirim ke dokter: penanda, tabel hasil, dan grafik tren."""
    trends_data = await build_trends(session, user_id, days)
    summary = await compute_doctor_summary(session, user_id, days, trends_data)
    filename = f"kira-ringkasan-{local_date(utcnow()).strftime('%Y%m%d')}.pdf"
    return Response(
        build_doctor_pdf(summary, trends_data),
        media_type="application/pdf",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )
