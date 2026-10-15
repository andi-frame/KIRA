"""Hak pemilik data: persetujuan, unduh data, hapus akun."""
import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.models import User
from app.ratelimit import login_limiter
from app.schemas.auth import PIN_PATTERN
from app.security import current_user_id, verify_pin
from app.services import account

router = APIRouter(prefix="/account", tags=["account"])


class DeleteIn(BaseModel):
    pin: str = Field(pattern=PIN_PATTERN)


@router.post("/consent")
async def give_consent(
    user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    when = await account.record_consent(session, user_id)
    return {"consented": True, "version": account.CONSENT_VERSION, "consented_at": when.isoformat()}


@router.get("/export")
async def export(user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)):
    return await account.export_account(session, user_id)


@router.post("/delete")
async def delete(
    body: DeleteIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    """Menghapus akun dan seluruh datanya secara permanen. Meminta PIN lagi agar tidak terhapus karena salah ketuk."""
    key = str(user_id)
    if login_limiter.blocked(key):
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Terlalu banyak percobaan. Coba lagi dalam 15 menit.")
    user = await session.get(User, user_id)
    if user is None or not verify_pin(body.pin, user.pin_hash):
        login_limiter.fail(key)
        raise HTTPException(status.HTTP_403_FORBIDDEN, "PIN salah")
    login_limiter.reset(key)
    await account.delete_account(session, user_id)
    return {"deleted": True}
