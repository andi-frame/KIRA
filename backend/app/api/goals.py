"""Target mingguan pribadi."""
import uuid

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.goals import GOAL_KINDS, validate_target
from app.db import get_session
from app.models import Goal
from app.security import current_user_id
from app.services import goals as goals_service

router = APIRouter(prefix="/goals", tags=["goals"])


class GoalIn(BaseModel):
    kind: str
    target: float | None = None


class GoalPatch(BaseModel):
    target: float


@router.get("")
async def list_goals(user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)) -> dict:
    return await goals_service.list_goals(session, user_id)


@router.post("")
async def create_goal(
    body: GoalIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    if body.kind not in GOAL_KINDS:
        raise HTTPException(422, "Jenis target tidak dikenal.")
    try:
        target = validate_target(body.kind, body.target if body.target is not None else GOAL_KINDS[body.kind]["default"])
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from None
    session.add(Goal(user_id=user_id, kind=body.kind, target=target))
    try:
        await session.commit()
    except IntegrityError:
        await session.rollback()
        raise HTTPException(409, "Target jenis ini sudah ada. Ubah saja angkanya.") from None
    return await goals_service.list_goals(session, user_id)


@router.patch("/{goal_id}")
async def change_goal(
    goal_id: uuid.UUID,
    body: GoalPatch,
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    goal = await session.get(Goal, goal_id)
    if goal is None or goal.user_id != user_id:
        raise HTTPException(404, "Target tidak ditemukan")
    try:
        goal.target = validate_target(goal.kind, body.target)
    except ValueError as exc:
        raise HTTPException(422, str(exc)) from None
    await session.commit()
    return await goals_service.list_goals(session, user_id)


@router.delete("/{goal_id}")
async def delete_goal(
    goal_id: uuid.UUID, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    goal = await session.get(Goal, goal_id)
    if goal is None or goal.user_id != user_id:
        raise HTTPException(404, "Target tidak ditemukan")
    await session.delete(goal)
    await session.commit()
    return {"ok": True}
