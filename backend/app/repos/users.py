import uuid

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import HealthProfile, User


async def get_by_phone(session: AsyncSession, phone: str) -> User | None:
    return (await session.execute(select(User).where(User.phone == phone))).scalar_one_or_none()


async def get(session: AsyncSession, user_id: uuid.UUID) -> User | None:
    return await session.get(User, user_id)


async def create(session: AsyncSession, phone: str, pin_hash: str) -> User | None:
    """Mengembalikan None bila nomor sudah terdaftar."""
    user = User(phone=phone, pin_hash=pin_hash)
    session.add(user)
    try:
        await session.flush()
    except IntegrityError:
        await session.rollback()
        return None
    session.add(HealthProfile(user_id=user.id))
    await session.commit()
    return user
