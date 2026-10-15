"""Tautan ringkasan untuk dokter: token acak, hanya hash yang disimpan, kedaluwarsa, bisa dicabut kapan saja."""
import uuid
from datetime import timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import ShareLink
from app.security import hash_token, new_refresh_token
from app.timeutil import utcnow

MAX_ACTIVE_LINKS = 5
DEFAULT_VALID_DAYS = 7
MAX_VALID_DAYS = 30


class TooManyLinks(Exception):
    pass


def is_active(link: ShareLink) -> bool:
    return link.revoked_at is None and link.expires_at > utcnow()


async def create(session: AsyncSession, user_id: uuid.UUID, *, days: int, valid_days: int) -> tuple[ShareLink, str]:
    """Membuat tautan baru. Token mentah hanya dikembalikan di sini, sekali ini."""
    active = (
        await session.execute(
            select(func.count())
            .select_from(ShareLink)
            .where(ShareLink.user_id == user_id, ShareLink.revoked_at.is_(None), ShareLink.expires_at > utcnow())
        )
    ).scalar_one()
    if active >= MAX_ACTIVE_LINKS:
        raise TooManyLinks
    token = new_refresh_token()
    link = ShareLink(
        user_id=user_id, token_hash=hash_token(token), days=days, expires_at=utcnow() + timedelta(days=valid_days)
    )
    session.add(link)
    await session.commit()
    return link, token


async def list_links(session: AsyncSession, user_id: uuid.UUID) -> list[ShareLink]:
    stmt = select(ShareLink).where(ShareLink.user_id == user_id).order_by(ShareLink.created_at.desc()).limit(20)
    return list((await session.execute(stmt)).scalars().all())


async def revoke(session: AsyncSession, user_id: uuid.UUID, link_id: uuid.UUID) -> bool:
    link = await session.get(ShareLink, link_id)
    if link is None or link.user_id != user_id:
        return False
    if link.revoked_at is None:
        link.revoked_at = utcnow()
        await session.commit()
    return True


async def resolve(session: AsyncSession, token: str) -> ShareLink | None:
    """Tautan yang masih berlaku untuk token ini, atau None (salah, kedaluwarsa, atau dicabut: tidak dibedakan)."""
    link = (
        await session.execute(select(ShareLink).where(ShareLink.token_hash == hash_token(token)))
    ).scalar_one_or_none()
    return link if link is not None and is_active(link) else None


async def mark_opened(session: AsyncSession, link: ShareLink) -> None:
    link.open_count += 1
    link.last_opened_at = utcnow()
    await session.commit()
