"""Ukur tensi di rumah 7 hari: mulai, catat bacaan, lihat kemajuan, selesaikan menjadi rata-rata."""
import uuid
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.security import current_user_id
from app.services import bp_protocol as svc
from app.services.projection_view import projection_payload
from app.services import risk

router = APIRouter(prefix="/bp-protocol", tags=["bp-protocol"])


class ReadingIn(BaseModel):
    sys: int = Field(ge=50, le=300)
    dia: int = Field(ge=30, le=200)
    session: Literal["morning", "evening"]
    measured_at: datetime | None = None


def _flag(flag) -> dict | None:
    return {"kind": flag.kind, "message": flag.message} if flag else None


@router.get("")
async def get_status(user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)) -> dict:
    return await svc.status(session, user_id)


@router.post("")
async def start(user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)) -> dict:
    try:
        await svc.start(session, user_id)
    except svc.ProtocolError as exc:
        raise HTTPException(409, str(exc)) from None
    return await svc.status(session, user_id)


@router.post("/readings")
async def add_reading(
    body: ReadingIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    try:
        row, flag = await svc.add_reading(
            session, user_id, sys=body.sys, dia=body.dia, session_name=body.session, measured_at=body.measured_at
        )
    except svc.ProtocolError as exc:
        raise HTTPException(422, str(exc)) from None
    return {"saved": row is not None, "red_flag": _flag(flag), **await svc.status(session, user_id)}


@router.post("/finish")
async def finish(user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)) -> dict:
    try:
        _, flag = await svc.finish(session, user_id)
    except svc.ProtocolError as exc:
        raise HTTPException(422, str(exc)) from None
    out = {"red_flag": _flag(flag), **await svc.status(session, user_id)}
    if flag is None:
        out["projection"] = projection_payload(await risk.compute_risk_state(session, user_id))
    return out


@router.delete("")
async def cancel(user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)) -> dict:
    if not await svc.cancel(session, user_id):
        raise HTTPException(404, "Tidak ada putaran yang berjalan")
    return {"ok": True}
