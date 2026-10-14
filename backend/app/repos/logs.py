import re
import uuid
from dataclasses import dataclass
from datetime import datetime, timedelta

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.targets import Totals
from app.models import Log, LogItem
from app.timeutil import start_of_today_utc, utcnow


@dataclass
class ItemData:
    name: str
    portion_g: float | None = None
    sugar_g: float | None = None
    sodium_mg: float | None = None
    fat_g: float | None = None
    kcal: float | None = None
    food_id: str | None = None


async def add_log(
    session: AsyncSession,
    user_id: uuid.UUID,
    *,
    kind: str,
    source: str,
    occurred_at: datetime,
    extracted: dict,
    raw_text: str | None,
    items: list[ItemData],
    commit: bool = True,
) -> Log:
    log = Log(user_id=user_id, kind=kind, source=source, occurred_at=occurred_at,
              extracted=extracted, raw_text=raw_text)
    session.add(log)
    await session.flush()
    for item in items:
        session.add(LogItem(log_id=log.id, **item.__dict__))
    await session.flush()
    if commit:
        await session.commit()
    return log


async def _with_items(session: AsyncSession, logs: list[Log]) -> list[tuple[Log, list[LogItem]]]:
    if not logs:
        return []
    items = (await session.execute(select(LogItem).where(LogItem.log_id.in_([lg.id for lg in logs])))).scalars().all()
    by_log: dict[uuid.UUID, list[LogItem]] = {}
    for item in items:
        by_log.setdefault(item.log_id, []).append(item)
    return [(lg, by_log.get(lg.id, [])) for lg in logs]


async def since(session: AsyncSession, user_id: uuid.UUID, *, hours: float = 0, days: float = 0):
    cutoff = utcnow() - timedelta(hours=hours, days=days)
    stmt = select(Log).where(Log.user_id == user_id, Log.occurred_at >= cutoff).order_by(Log.occurred_at.desc())
    return await _with_items(session, list((await session.execute(stmt)).scalars().all()))


async def today_totals(session: AsyncSession, user_id: uuid.UUID) -> Totals:
    stmt = (
        select(
            func.coalesce(func.sum(LogItem.sugar_g), 0),
            func.coalesce(func.sum(LogItem.sodium_mg), 0),
            func.coalesce(func.sum(LogItem.fat_g), 0),
        )
        .join(Log, Log.id == LogItem.log_id)
        .where(Log.user_id == user_id, Log.occurred_at >= start_of_today_utc())
    )
    sugar, sodium, fat = (await session.execute(stmt)).one()
    return Totals(float(sugar), float(sodium), float(fat))


async def search_older(
    session: AsyncSession, user_id: uuid.UUID, query: str, *, older_than_hours: float = 72, limit: int = 5
) -> list[Log]:
    words = [w for w in re.findall(r"\w+", query.lower()) if len(w) >= 4][:5]
    if not words:
        return []
    cutoff = utcnow() - timedelta(hours=older_than_hours)
    stmt = (
        select(Log)
        .where(Log.user_id == user_id, Log.occurred_at < cutoff,
               or_(*[Log.raw_text.ilike(f"%{w}%") for w in words]))
        .order_by(Log.occurred_at.desc())
        .limit(limit)
    )
    return list((await session.execute(stmt)).scalars().all())


async def get_owned(session: AsyncSession, user_id: uuid.UUID, log_id: uuid.UUID) -> Log | None:
    log = await session.get(Log, log_id)
    return log if log is not None and log.user_id == user_id else None
