import re
import uuid
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.security import current_user_id
from app.services import plan as plan_service

router = APIRouter(prefix="/plan", tags=["plan"])

_HHMM = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")
MealSlot = Literal["breakfast", "lunch", "snack", "dinner"]


def _time(v: str | None) -> str | None:
    if v is not None and not _HHMM.match(v):
        raise ValueError("format jam HH:MM")
    return v


class QuietHours(BaseModel):
    start: str
    end: str

    @field_validator("start", "end")
    @classmethod
    def _check(cls, v: str) -> str:
        return _time(v)


class PlanPrefsIn(BaseModel):
    wake_time: str | None = None
    meal_times: dict[MealSlot, str] | None = None
    exercise_time: str | None = None
    exercise_days: list[int] | None = Field(default=None, max_length=7)
    exercise_kinds: list[str] | None = Field(default=None, max_length=6)
    strength_days: int | None = Field(default=None, ge=0, le=3)
    goal: Literal["jaga", "turun_berat", "aktif"] | None = None
    channels: dict[Literal["app", "whatsapp"], bool] | None = None
    reminders: dict[Literal["meals", "exercise", "sleep", "weekly_plan"], bool] | None = None
    quiet_hours: QuietHours | None = None

    @field_validator("wake_time", "exercise_time")
    @classmethod
    def _times(cls, v: str | None) -> str | None:
        return _time(v)

    @field_validator("meal_times")
    @classmethod
    def _meal_times(cls, v: dict | None) -> dict | None:
        for t in (v or {}).values():
            _time(t)
        return v

    @field_validator("exercise_days")
    @classmethod
    def _days(cls, v: list[int] | None) -> list[int] | None:
        if v is not None and any(d < 0 or d > 6 for d in v):
            raise ValueError("hari 0 (Senin) sampai 6 (Minggu)")
        return sorted(set(v)) if v is not None else None

    @field_validator("exercise_kinds")
    @classmethod
    def _kinds(cls, v: list[str] | None) -> list[str] | None:
        if v is None:
            return None
        cleaned = [k.strip()[:40] for k in v if k and k.strip()]
        return cleaned or ["jalan cepat"]


class SwapIn(BaseModel):
    slot: MealSlot


@router.get("/preferences")
async def get_preferences(user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)) -> dict:
    return await plan_service.get_prefs(session, user_id)


@router.put("/preferences")
async def put_preferences(body: PlanPrefsIn, user_id: uuid.UUID = Depends(current_user_id),
                          session: AsyncSession = Depends(get_session)) -> dict:
    data = body.model_dump(exclude_none=True)
    if "quiet_hours" in data:
        data["quiet_hours"] = body.quiet_hours.model_dump()
    return await plan_service.save_prefs(session, user_id, data)


@router.get("/today")
async def today(user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)) -> dict:
    """Usulan hari ini (makan, olahraga, tidur), disesuaikan dengan yang sudah dicatat hari ini."""
    return await plan_service.plan_today(session, user_id)


@router.get("/week")
async def week(user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)) -> dict:
    return await plan_service.plan_week(session, user_id)


@router.post("/today/swap")
async def swap(body: SwapIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)) -> dict:
    try:
        return await plan_service.swap(session, user_id, body.slot)
    except ValueError:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Bagian rencana tidak dikenal") from None
