import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import WeeklySummary


async def latest(session: AsyncSession, user_id: uuid.UUID) -> WeeklySummary | None:
    stmt = (
        select(WeeklySummary)
        .where(WeeklySummary.user_id == user_id)
        .order_by(WeeklySummary.week_start.desc())
        .limit(1)
    )
    return (await session.execute(stmt)).scalar_one_or_none()
