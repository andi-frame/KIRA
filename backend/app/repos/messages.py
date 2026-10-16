import uuid

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Message
from app.timeutil import start_of_today_utc, utcnow


async def save(
    session: AsyncSession,
    user_id: uuid.UUID,
    role: str,
    content: str | None,
    channel: str,
    tool_calls: list | None = None,
    commit: bool = True,
    meta: dict | None = None,
) -> None:
    # Waktu diisi di sini, bukan server_default now(): dalam satu transaksi now() sama untuk pesan pengguna dan balasan.
    session.add(Message(user_id=user_id, role=role, content=content, channel=channel, tool_calls=tool_calls, meta=meta,
                        created_at=utcnow()))
    if commit:
        await session.commit()


async def today(session: AsyncSession, user_id: uuid.UUID) -> list[Message]:
    """Obrolan hari ini (tanggal WIB), urut waktu. Satu riwayat per hari."""
    stmt = (
        select(Message)
        .where(Message.user_id == user_id, Message.role.in_(["user", "assistant"]),
               Message.created_at >= start_of_today_utc())
        .order_by(Message.created_at, (Message.role == "assistant"), Message.id)  # seri: pesan pengguna dulu
    )
    return list((await session.execute(stmt)).scalars().all())


async def purge_before_today(session: AsyncSession, user_id: uuid.UUID | None = None, *, commit: bool = True) -> int:
    """Hapus obrolan sebelum hari ini: tiap hari hanya satu riwayat, hari baru mulai bersih. Tanpa user_id = semua pengguna."""
    stmt = delete(Message).where(Message.created_at < start_of_today_utc())
    if user_id is not None:
        stmt = stmt.where(Message.user_id == user_id)
    result = await session.execute(stmt)
    if commit:
        await session.commit()
    return result.rowcount or 0


async def clear_today(session: AsyncSession, user_id: uuid.UUID) -> int:
    result = await session.execute(
        delete(Message).where(Message.user_id == user_id, Message.created_at >= start_of_today_utc())
    )
    await session.commit()
    return result.rowcount or 0


async def last(session: AsyncSession, user_id: uuid.UUID, n: int = 8) -> list[Message]:
    stmt = (
        select(Message)
        .where(Message.user_id == user_id, Message.role.in_(["user", "assistant"]))
        .order_by(Message.created_at.desc(), (Message.role == "assistant").desc())
        .limit(n)
    )
    return list(reversed((await session.execute(stmt)).scalars().all()))
