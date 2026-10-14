import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Message


async def save(
    session: AsyncSession,
    user_id: uuid.UUID,
    role: str,
    content: str | None,
    channel: str,
    tool_calls: list | None = None,
    commit: bool = True,
) -> None:
    session.add(Message(user_id=user_id, role=role, content=content, channel=channel, tool_calls=tool_calls))
    if commit:
        await session.commit()


async def last(session: AsyncSession, user_id: uuid.UUID, n: int = 8) -> list[Message]:
    stmt = (
        select(Message)
        .where(Message.user_id == user_id, Message.role.in_(["user", "assistant"]))
        .order_by(Message.created_at.desc())
        .limit(n)
    )
    return list(reversed((await session.execute(stmt)).scalars().all()))
