import uuid
from datetime import timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import AccessLog
from app.timeutil import utcnow

# Satu orang yang membuka berulang kali dalam rentang ini dicatat sekali, supaya riwayat tetap terbaca.
COLLAPSE_WINDOW = timedelta(minutes=30)


async def record(
    session: AsyncSession,
    owner_id: uuid.UUID,
    *,
    kind: str,
    viewer_name: str,
    viewer_id: uuid.UUID | None = None,
    detail: str | None = None,
) -> bool:
    """Mencatat satu akses. False bila sama dengan akses terakhir dalam rentang COLLAPSE_WINDOW."""
    recent_same = select(AccessLog.id).where(
        AccessLog.owner_id == owner_id,
        AccessLog.kind == kind,
        AccessLog.viewer_name == viewer_name,
        AccessLog.detail.is_not_distinct_from(detail),
        AccessLog.created_at >= utcnow() - COLLAPSE_WINDOW,
    )
    if viewer_id is not None:
        recent_same = recent_same.where(AccessLog.viewer_id == viewer_id)
    if (await session.execute(recent_same.limit(1))).first():
        return False
    session.add(AccessLog(owner_id=owner_id, viewer_id=viewer_id, viewer_name=viewer_name, kind=kind, detail=detail))
    await session.commit()
    return True


async def recent(session: AsyncSession, owner_id: uuid.UUID, limit: int = 50) -> list[AccessLog]:
    stmt = select(AccessLog).where(AccessLog.owner_id == owner_id).order_by(AccessLog.created_at.desc()).limit(limit)
    return list((await session.execute(stmt)).scalars().all())
