"""Kiriman yang aman diulang. Klien (antrean offline) mengirim `Idempotency-Key` unik per kiriman; bila jaringan putus
setelah server mencatat tetapi sebelum jawaban sampai, kiriman ulang mendapat jawaban yang sama dan tidak tercatat dua kali."""
import re
import uuid
from datetime import timedelta

from fastapi import Header, HTTPException
from sqlalchemy import delete
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import IdempotencyKey
from app.timeutil import utcnow

KEEP_FOR = timedelta(days=7)
_KEY = re.compile(r"^[A-Za-z0-9_.:-]{8,80}$")


def idempotency_key(idempotency_key: str | None = Header(default=None)) -> str | None:
    if idempotency_key is None:
        return None
    if not _KEY.fullmatch(idempotency_key):
        raise HTTPException(422, "Idempotency-Key harus 8-80 karakter huruf, angka, titik, titik dua, garis, atau garis bawah.")
    return idempotency_key


async def replay(session: AsyncSession, user_id: uuid.UUID, key: str | None) -> dict | None:
    if key is None:
        return None
    row = await session.get(IdempotencyKey, (user_id, key))
    return row.response if row else None


async def remember(session: AsyncSession, user_id: uuid.UUID, key: str | None, response: dict) -> None:
    """Menyimpan jawaban. Kiriman kembar yang berjalan bersamaan: yang pertama menang, tanpa error."""
    if key is None:
        return
    await session.execute(delete(IdempotencyKey).where(IdempotencyKey.created_at < utcnow() - KEEP_FOR))
    stmt = insert(IdempotencyKey).values(user_id=user_id, key=key, response=response).on_conflict_do_nothing()
    await session.execute(stmt)
    await session.commit()
