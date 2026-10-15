import uuid
from datetime import timedelta

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import AuthSession
from app.security import hash_token, new_refresh_token
from app.timeutil import utcnow


def _expiry():
    return utcnow() + timedelta(days=settings.refresh_expire_days)


async def start(session: AsyncSession, user_id: uuid.UUID) -> str:
    """Membuka sesi baru untuk satu perangkat dan mengembalikan token penyegarnya (sekali ini saja terlihat)."""
    await session.execute(delete(AuthSession).where(AuthSession.expires_at < utcnow()))
    token = new_refresh_token()
    session.add(AuthSession(user_id=user_id, token_hash=hash_token(token), expires_at=_expiry()))
    await session.commit()
    return token


async def rotate(session: AsyncSession, token: str) -> tuple[uuid.UUID, str] | None:
    """Menukar token penyegar dengan yang baru. Token lama langsung tidak berlaku; kedaluwarsa menggeser (sliding)."""
    row = (
        await session.execute(select(AuthSession).where(AuthSession.token_hash == hash_token(token)).with_for_update())
    ).scalar_one_or_none()
    if row is None or row.expires_at < utcnow():
        return None
    fresh = new_refresh_token()
    row.token_hash, row.expires_at, row.last_used_at = hash_token(fresh), _expiry(), utcnow()
    await session.commit()
    return row.user_id, fresh


async def revoke(session: AsyncSession, token: str) -> None:
    await session.execute(delete(AuthSession).where(AuthSession.token_hash == hash_token(token)))
    await session.commit()


async def revoke_all(session: AsyncSession, user_id: uuid.UUID, *, commit: bool = True) -> None:
    await session.execute(delete(AuthSession).where(AuthSession.user_id == user_id))
    if commit:
        await session.commit()
