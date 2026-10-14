import uuid
from dataclasses import asdict

from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.constants import DAILY_LIMITS
from app.core_calc.targets import remaining_targets
from app.models import User
from app.repos import logs as logs_repo


async def today_targets(session: AsyncSession, user_id: uuid.UUID) -> dict:
    user = await session.get(User, user_id)
    mode = user.mode if user else "prevention"
    consumed = await logs_repo.today_totals(session, user_id)
    return {
        "mode": mode,
        "limits": DAILY_LIMITS,
        "consumed": asdict(consumed),
        "remaining": asdict(remaining_targets(consumed, mode)),
    }
