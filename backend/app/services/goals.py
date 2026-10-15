"""Target mingguan: daftar target beserta kemajuan minggu ini dan ketercapaian empat minggu terakhir."""
import uuid
from datetime import date, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.goals import GOAL_KINDS, Progress, evaluate
from app.models import Goal
from app.services.trends import daily_series
from app.timeutil import local_date, utcnow

HISTORY_WEEKS = 4


def week_start(today: date) -> date:
    return today - timedelta(days=today.weekday())


def kinds_out() -> list[dict]:
    return [
        {"kind": k, "label": v["label"], "unit": v["unit"], "direction": v["direction"],
         "default": v["default"], "min": v["lo"], "max": v["hi"]}
        for k, v in GOAL_KINDS.items()
    ]


def _progress_out(p: Progress) -> dict:
    return {
        "current": p.current, "target": p.target, "direction": p.direction, "met": p.met,
        "status": p.status, "remaining": p.remaining, "fraction": round(p.fraction, 3),
    }


async def list_goals(session: AsyncSession, user_id: uuid.UUID) -> dict:
    today = local_date(utcnow())
    this_monday = week_start(today)
    rows = list((await session.execute(select(Goal).where(Goal.user_id == user_id).order_by(Goal.created_at))).scalars().all())

    first = this_monday - timedelta(weeks=HISTORY_WEEKS)
    series = await daily_series(session, user_id, first, this_monday + timedelta(days=6)) if rows else []
    by_date = {d["date"]: d for d in series}

    def days_of(monday: date) -> list[dict]:
        return [by_date[(monday + timedelta(days=i)).isoformat()] for i in range(7)]

    goals = []
    for g in rows:
        now = evaluate(g.kind, g.target, days_of(this_monday))
        history = []
        for w in range(HISTORY_WEEKS, 0, -1):
            monday = this_monday - timedelta(weeks=w)
            days = days_of(monday)
            if not any(d["logged"] for d in days):
                history.append({"week_start": monday.isoformat(), "met": None, "current": None})  # tidak ada data: bukan "gagal"
                continue
            p = evaluate(g.kind, g.target, days)
            history.append({"week_start": monday.isoformat(), "met": p.met, "current": p.current})
        spec = GOAL_KINDS[g.kind]
        goals.append({
            "id": str(g.id), "kind": g.kind, "label": spec["label"], "unit": spec["unit"],
            "progress": _progress_out(now), "history": history,
            "met_weeks": sum(1 for h in history if h["met"]), "weeks_with_data": sum(1 for h in history if h["met"] is not None),
        })
    return {
        "goals": goals,
        "kinds": kinds_out(),
        "week": {"start": this_monday.isoformat(), "end": (this_monday + timedelta(days=6)).isoformat(),
                 "days_left": 6 - today.weekday()},
    }
