import re
import uuid

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import HealthProfile, User

_PHONE = re.compile(r"^\+?\d{8,15}$")


class DuplicateError(Exception):
    """Pendaftaran atau penggantian ditolak karena bentrok. field: phone | username."""

    def __init__(self, field: str):
        super().__init__(field)
        self.field = field


async def get_by_phone(session: AsyncSession, phone: str) -> User | None:
    return (await session.execute(select(User).where(User.phone == phone))).scalar_one_or_none()


async def get_by_username(session: AsyncSession, username: str) -> User | None:
    return (
        await session.execute(select(User).where(func.lower(User.username) == username.lower()))
    ).scalar_one_or_none()


async def get_by_identifier(session: AsyncSession, identifier: str) -> User | None:
    """Nomor HP bila bentuknya nomor, selain itu nama pengguna. Nama pengguna selalu diawali huruf, jadi tidak ambigu."""
    ident = identifier.strip()
    if _PHONE.fullmatch(ident):
        return await get_by_phone(session, ident)
    return await get_by_username(session, ident)


async def get(session: AsyncSession, user_id: uuid.UUID) -> User | None:
    return await session.get(User, user_id)


def _conflict_field(error: IntegrityError) -> str:
    return "username" if "ux_users_username_lower" in str(error.orig) else "phone"


async def create(session: AsyncSession, phone: str, pin_hash: str, username: str | None = None) -> User:
    """Membuat akun. DuplicateError bila nomor atau nama pengguna sudah dipakai."""
    user = User(phone=phone, pin_hash=pin_hash, username=username)
    session.add(user)
    try:
        await session.flush()
    except IntegrityError as exc:
        await session.rollback()
        raise DuplicateError(_conflict_field(exc)) from exc
    session.add(HealthProfile(user_id=user.id))
    await session.commit()
    return user


async def set_username(session: AsyncSession, user_id: uuid.UUID, username: str) -> str:
    user = await session.get(User, user_id)
    user.username = username
    try:
        await session.commit()
    except IntegrityError as exc:
        await session.rollback()
        raise DuplicateError("username") from exc
    return username
