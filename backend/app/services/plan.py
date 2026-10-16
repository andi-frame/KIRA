"""Rencana harian/mingguan dari data pengguna: profil, mode, catatan 14 hari, hasil cek, dan preferensi rencana.

Logika pemilihan ada di core_calc/planner.py (fungsi murni); di sini hanya mengumpulkan masukan dan menyimpan
preferensi serta penggantian usulan.
"""
import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.planner import (
    MEAL_SLOTS,
    Catalog,
    PlanContext,
    PlanPrefs,
    day_plan,
    plan_range,
    recent_ids_before,
    slot_for_time,
)
from app.core_calc.triage import triage_flags
from app.models import HealthProfile, PlanOverride, PlanPreference, User
from app.repos import foods as foods_repo
from app.repos.profiles import age_from
from app.services import history
from app.services.trends import clinical_trends, latest_for_triage
from app.timeutil import WIB, local_date, utcnow

DEFAULT_MEAL_TIMES = {"breakfast": "06:30", "lunch": "12:00", "snack": "15:30", "dinner": "18:30"}
DEFAULT_REMINDERS = {"meals": True, "exercise": True, "sleep": True, "weekly_plan": True}
WEEK_DAYS = 7


def prefs_out(row: PlanPreference | None) -> dict:
    if row is None:
        return {"wake_time": "06:00", "meal_times": dict(DEFAULT_MEAL_TIMES), "exercise_time": "17:00",
                "exercise_days": [0, 1, 2, 3, 4], "exercise_kinds": ["jalan cepat"], "strength_days": 0, "goal": "jaga",
                "channels": {"app": True, "whatsapp": False}, "reminders": dict(DEFAULT_REMINDERS),
                "quiet_hours": {"start": "21:30", "end": "06:00"}}
    return {"wake_time": row.wake_time, "meal_times": {**DEFAULT_MEAL_TIMES, **(row.meal_times or {})},
            "exercise_time": row.exercise_time, "exercise_days": list(row.exercise_days),
            "exercise_kinds": list(row.exercise_kinds), "strength_days": row.strength_days, "goal": row.goal,
            "channels": {"app": True, "whatsapp": False, **(row.channels or {})},
            "reminders": {**DEFAULT_REMINDERS, **(row.reminders or {})}, "quiet_hours": row.quiet_hours}


async def get_prefs(session: AsyncSession, user_id: uuid.UUID) -> dict:
    return prefs_out(await session.get(PlanPreference, user_id))


async def save_prefs(session: AsyncSession, user_id: uuid.UUID, data: dict) -> dict:
    values = {k: v for k, v in data.items() if v is not None}
    stmt = insert(PlanPreference).values(user_id=user_id, **values)
    await session.execute(stmt.on_conflict_do_update(
        index_elements=["user_id"], set_={**{k: getattr(stmt.excluded, k) for k in values}, "updated_at": utcnow()}))
    await session.commit()
    session.expire_all()
    return await get_prefs(session, user_id)


async def _context(session: AsyncSession, user_id: uuid.UUID, today: date) -> tuple[PlanContext, PlanPrefs, list]:
    user = await session.get(User, user_id)
    profile = await session.get(HealthProfile, user_id)
    prefs = await get_prefs(session, user_id)
    mode = user.mode if user else "prevention"
    rows = await history.logs_between(session, user_id, today - timedelta(days=13), today)
    sleep_by_day: dict[date, float] = {}
    active = 0.0
    for lg, _ in rows:
        if lg.kind == "sleep" and lg.extracted.get("hours"):
            day = local_date(lg.occurred_at)
            sleep_by_day[day] = max(sleep_by_day.get(day, 0.0), float(lg.extracted["hours"]))
        elif lg.kind == "activity":
            active += float(lg.extracted.get("minutes", 0) or 0)
    last7 = [h for d, h in sleep_by_day.items() if d > today - timedelta(days=7)]
    has_logs = bool(rows)
    flags = triage_flags(latest_for_triage(await clinical_trends(session, user_id)), None)
    ctx = PlanContext(
        user_key=str(user_id), limits=history.limits_for(mode), mode=mode,
        age=age_from(profile.birth_date) if profile else None, sex=profile.sex if profile else None,
        height_cm=profile.height_cm if profile else None, weight_kg=profile.weight_kg if profile else None,
        recent_sleep_avg=round(sum(last7) / len(last7), 1) if last7 else None,
        recent_weekly_active=round(active / 2, 1) if has_logs else None,
        exercise_blocked=any(f["level"] == "perhatian" and f["kind"] == "blood_pressure" for f in flags),
    )
    dislikes = tuple(str(x) for x in ((profile.food_preferences or {}).get("dislikes") or [])) if profile else ()
    plan_prefs = PlanPrefs(
        wake_time=prefs["wake_time"], meal_times=prefs["meal_times"], exercise_time=prefs["exercise_time"],
        exercise_days=tuple(prefs["exercise_days"]), exercise_kinds=tuple(prefs["exercise_kinds"]),
        strength_days=prefs["strength_days"], goal=prefs["goal"], dislikes=dislikes,
    )
    return ctx, plan_prefs, rows


async def _catalog(session: AsyncSession) -> Catalog:
    cat = await foods_repo.catalog(session)
    return Catalog(cat.dishes, cat.by_id)


async def _offsets(session: AsyncSession, user_id: uuid.UUID, start: date, end: date) -> dict[str, dict[str, int]]:
    rows = (await session.execute(select(PlanOverride).where(
        PlanOverride.user_id == user_id, PlanOverride.date >= start, PlanOverride.date <= end))).scalars().all()
    out: dict[str, dict[str, int]] = defaultdict(dict)
    for r in rows:
        out[r.date.isoformat()][r.slot] = int(r.replacement.get("offset", 0))
    return dict(out)


async def plan_today(session: AsyncSession, user_id: uuid.UUID, now: datetime | None = None) -> dict:
    now = now or utcnow()
    today = local_date(now)
    ctx, prefs, rows = await _context(session, user_id, today)
    catalog = await _catalog(session)
    offsets = await _offsets(session, user_id, today - timedelta(days=3), today)
    todays = [(lg, items) for lg, items in rows if local_date(lg.occurred_at) == today]
    eaten = [i for lg, items in todays if lg.kind in ("meal", "drink") for i in items]
    consumed = {k: sum(float(getattr(i, k) or 0) for i in eaten) for k in ("kcal", "sugar_g", "sodium_mg", "fat_g")}
    done = {slot_for_time(lg.occurred_at.astimezone(WIB)) for lg, _ in todays if lg.kind == "meal"}
    plan = day_plan(today, ctx, prefs, catalog, recent=recent_ids_before(today, ctx, prefs, catalog, offsets),
                    offsets=offsets.get(today.isoformat()), consumed=consumed if eaten else None, done_slots=done)
    active_today = sum(float(lg.extracted.get("minutes", 0) or 0) for lg, _ in todays if lg.kind == "activity")
    if plan["exercise"]:
        plan["exercise"]["done_minutes"] = round(active_today, 1)
        plan["exercise"]["done"] = bool(plan["exercise"]["minutes"]) and active_today >= plan["exercise"]["minutes"]
    plan["consumed"] = {k: round(v, 1) for k, v in consumed.items()}
    return plan


async def plan_week(session: AsyncSession, user_id: uuid.UUID, now: datetime | None = None) -> dict:
    today = local_date(now or utcnow())
    ctx, prefs, _ = await _context(session, user_id, today)
    catalog = await _catalog(session)
    offsets = await _offsets(session, user_id, today - timedelta(days=3), today + timedelta(days=WEEK_DAYS))
    days = plan_range(today, WEEK_DAYS, ctx, prefs, catalog, offsets)
    return {"start": today.isoformat(), "days": days}


async def swap(session: AsyncSession, user_id: uuid.UUID, slot: str, now: datetime | None = None) -> dict:
    """Ganti satu usulan hari ini dengan alternatif berikutnya yang tetap memenuhi anggaran."""
    if slot not in MEAL_SLOTS:
        raise ValueError(slot)
    today = local_date(now or utcnow())
    row = await session.get(PlanOverride, (user_id, today, slot))
    if row is None:
        session.add(PlanOverride(user_id=user_id, date=today, slot=slot, replacement={"offset": 1}))
    else:
        row.replacement = {"offset": int(row.replacement.get("offset", 0)) + 1}
    await session.commit()
    return await plan_today(session, user_id, now)
