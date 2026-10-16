"""Beranda: satu panggilan berisi kondisi hari ini, minggu ini, sinyal kebiasaan, proyeksi, dan langkah berikutnya.

Semua angka dari fungsi murni yang sudah ada (core_calc) dan catatan pengguna sendiri; tidak ada yang dari LLM.
"""
import uuid
from collections import defaultdict
from datetime import date, datetime, timedelta

from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.goals import SLEEP_TARGET_HOURS
from app.core_calc.habits import DAILY_ACTIVE_TARGET, habit_report, next_best_action, week_metrics, weekly_changes
from app.core_calc.triage import triage_flags
from app.models import User
from app.services import bp_protocol, goals as goals_service, history, plan as plan_service, risk
from app.services.projection_view import projection_payload
from app.services.trends import clinical_trends, latest_for_triage, risk_history
from app.timeutil import WIB, local_date, utcnow

HISTORY_DAYS = 28  # cukup untuk pola tidur (butuh >= 3 hari di tiap kelompok) dan perbandingan dua minggu
RISK_HISTORY_DAYS = 30


def _day_stats(day: date, rows: list) -> dict:
    eaten = [i for lg, items in rows if lg.kind in ("meal", "drink") for i in items]
    sweet = 0.0
    for lg, items in rows:
        if lg.kind == "drink":
            count = float(lg.extracted.get("count", 1) or 1)
            if sum(float(i.sugar_g or 0) for i in items) / count >= risk.SWEET_DRINK_MIN_SUGAR_G:
                sweet += count
    activity = [float(lg.extracted.get("minutes", 0) or 0) for lg, _ in rows if lg.kind == "activity"]
    sleep = [float(lg.extracted["hours"]) for lg, _ in rows if lg.kind == "sleep" and lg.extracted.get("hours")]
    total = lambda k: round(sum(float(getattr(i, k) or 0) for i in eaten), 1)  # noqa: E731
    return {
        "date": day.isoformat(),
        "logged": bool(rows),
        "kcal": total("kcal") if rows else None,
        "sugar_g": total("sugar_g") if rows else None,
        "sodium_mg": total("sodium_mg") if rows else None,
        "fat_g": total("fat_g") if rows else None,
        "sweet_drinks": sweet if rows else None,
        "active_minutes": round(sum(activity), 1) if activity else None,
        "sleep_hours": round(max(sleep), 1) if sleep else None,
        "meals": sum(1 for lg, _ in rows if lg.kind == "meal"),
        "last_log_at": max(lg.occurred_at for lg, _ in rows).isoformat() if rows else None,
    }


async def build_dashboard(session: AsyncSession, user_id: uuid.UUID, now: datetime | None = None) -> dict:
    now = now or utcnow()
    today = local_date(now)
    user = await session.get(User, user_id)
    mode = user.mode if user else "prevention"
    limits = history.limits_for(mode)

    start = today - timedelta(days=HISTORY_DAYS - 1)
    by_day: dict[date, list] = defaultdict(list)
    for lg, items in await history.logs_between(session, user_id, start, today):
        by_day[local_date(lg.occurred_at)].append((lg, items))
    days = [_day_stats(start + timedelta(days=o), by_day.get(start + timedelta(days=o), [])) for o in range(HISTORY_DAYS)]

    state = await risk.compute_risk_state(session, user_id)
    clinical = await clinical_trends(session, user_id)
    flags = triage_flags(latest_for_triage(clinical), None if state.needs_profile else state.category_high)
    report = habit_report(days, limits, mode, flags)

    t = days[-1]
    open_checks = await risk.open_recommendations(session, user_id)
    open_check = {"test_kind": open_checks[0].test_kind, "reason": open_checks[0].reason} if open_checks else None
    protocol = await bp_protocol.latest(session, user_id)
    action = next_best_action(
        hour=now.astimezone(WIB).hour, meals_logged=t["meals"], active_minutes_today=t["active_minutes"] or 0,
        has_attention_result=any(f["level"] == "perhatian" for f in flags), open_check=open_check,
        bp_protocol_active=protocol is not None and protocol.status == "active",
    )
    week, prev = days[-7:], days[-14:-7]
    goals = (await goals_service.list_goals(session, user_id))["goals"]
    plan = await plan_service.plan_today(session, user_id, now)
    plan_card = {
        "meals": [{k: m.get(k) for k in ("slot", "label", "time", "title", "done", "over_budget")}
                  | {"kcal": (m.get("totals") or {}).get("kcal")} for m in plan["meals"]],
        "exercise": plan["exercise"] and {k: plan["exercise"].get(k) for k in
                                          ("minutes", "activity", "time", "done", "done_minutes", "blocked", "strength")},
        "sleep": {k: plan["sleep"][k] for k in ("hours", "bedtime", "wake_time")},
        "adapted": plan["adapted"],
    }
    return {
        "today": {
            "date": today.isoformat(),
            "nutrition": {"kcal": t["kcal"] or 0, "sugar_g": t["sugar_g"] or 0, "sodium_mg": t["sodium_mg"] or 0,
                          "fat_g": t["fat_g"] or 0, "limits": limits, "kcal_target": plan["energy"]["kcal"]},
            "activity_minutes": t["active_minutes"] or 0,
            "activity_target_today": DAILY_ACTIVE_TARGET,
            "sleep_hours_last_night": t["sleep_hours"],
            "sleep_target": {"hours": plan["sleep"]["hours"], "bedtime": plan["sleep"]["bedtime"],
                             "minimum_hours": SLEEP_TARGET_HOURS},
            "meals_logged": t["meals"],
            "last_log_at": t["last_log_at"],
        },
        "week": {
            "days": [{k: d[k] for k in ("date", "logged", "kcal", "sugar_g", "active_minutes", "sleep_hours")} for d in week],
            "vs_last_week": weekly_changes(week_metrics(week), week_metrics(prev)) if week_metrics(week) else None,
        },
        "signals": report["signals"],
        "data_quality": report["data_quality"],
        "logged_days": report["logged_days"],
        "risk": projection_payload(state),
        "risk_history": await risk_history(session, user_id, RISK_HISTORY_DAYS),
        "plan_today": plan_card,
        "goals": goals,
        "open_check": open_check,
        "next_best_action": action,
    }
