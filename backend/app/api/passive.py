"""Sinkronisasi data pasif dari perangkat (Health Connect): langkah dan tidur.

Klien mengirim catatan mentah; menit aktif dihitung di sini (core_calc.steps), bukan di aplikasi. Sinkron ulang
menggantikan catatan health_connect sejak hari paling awal di kiriman, jadi tidak pernah menggandakan.
"""
import uuid
from datetime import date, datetime, time, timedelta

from fastapi import APIRouter, Depends
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import delete
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.steps import StepSegment, moderate_minutes_by_day, steps_by_day
from app.db import get_session
from app.models import Log
from app.repos import logs as logs_repo
from app.security import current_user_id
from app.services import risk
from app.timeutil import WIB, local_date, utcnow

router = APIRouter(prefix="/sync", tags=["sync"])

SOURCE = "health_connect"
WINDOW_DAYS = 31
MIN_SLEEP_HOURS, MAX_SLEEP_HOURS = 1.5, 16.0  # di luar ini: tidur sebentar (kantuk) atau galat data


def _aware(v: datetime) -> datetime:
    return v if v.tzinfo else v.replace(tzinfo=WIB)


class StepSegmentIn(BaseModel):
    start: datetime
    end: datetime
    count: int = Field(ge=0, le=100_000)

    _tz = field_validator("start", "end")(_aware)


class SleepSessionIn(BaseModel):
    start: datetime
    end: datetime

    _tz = field_validator("start", "end")(_aware)


class PassiveSyncIn(BaseModel):
    steps: list[StepSegmentIn] = Field(default_factory=list, max_length=20_000)
    sleep: list[SleepSessionIn] = Field(default_factory=list, max_length=100)


def _noon(day: date) -> datetime:
    return min(datetime.combine(day, time(12, 0), tzinfo=WIB), utcnow())


@router.post("/passive")
async def sync_passive(
    body: PassiveSyncIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict[str, int]:
    now = utcnow()
    earliest_day = local_date(now) - timedelta(days=WINDOW_DAYS)

    def in_window(moment: datetime) -> bool:
        return earliest_day <= local_date(moment) and moment <= now + timedelta(hours=1)

    segments = [StepSegment(s.start, s.end, s.count) for s in body.steps if in_window(s.start)]
    minutes, totals = moderate_minutes_by_day(segments), steps_by_day(segments)
    nights = []
    for s in body.sleep:
        hours = (s.end - s.start).total_seconds() / 3600
        if in_window(s.end) and MIN_SLEEP_HOURS <= hours <= MAX_SLEEP_HOURS:
            nights.append((s, round(hours, 1)))

    days_touched = [*totals, *(local_date(s.end) for s, _ in nights)]
    if not days_touched:
        return {"activity_days": 0, "sleep_nights": 0}

    cutoff = datetime.combine(min(days_touched), time.min, tzinfo=WIB)
    await session.execute(
        delete(Log).where(Log.user_id == user_id, Log.source == SOURCE, Log.occurred_at >= cutoff)
    )
    for day, count in totals.items():
        await logs_repo.add_log(
            session, user_id, kind="activity", source=SOURCE, occurred_at=_noon(day), raw_text=None, items=[],
            extracted={"kind": "jalan (perkiraan dari langkah)", "minutes": round(minutes.get(day, 0.0), 1),
                       "steps": count},
            commit=False,
        )
    for s, hours in nights:
        await logs_repo.add_log(
            session, user_id, kind="sleep", source=SOURCE, occurred_at=s.end.astimezone(WIB), raw_text=None,
            items=[],
            extracted={"bed_time": s.start.astimezone(WIB).strftime("%H:%M"),
                       "wake_time": s.end.astimezone(WIB).strftime("%H:%M"), "hours": hours},
            commit=False,
        )
    state = await risk.compute_risk_state(session, user_id)
    await risk.save_snapshot(session, user_id, state, commit=False)
    await risk.refresh_check_recommendation(session, user_id, state, commit=False)
    await session.commit()
    return {"activity_days": len(totals), "sleep_nights": len(nights)}
