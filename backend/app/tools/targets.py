from dataclasses import asdict

from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool

from app.core_calc.constants import DAILY_LIMITS
from app.core_calc.targets import remaining_targets
from app.models import User
from app.repos import logs as logs_repo
from app.tools._ctx import ctx


@tool
async def sisa_target_harian(config: RunnableConfig) -> dict:
    """Sisa batas gula, garam (natrium), dan lemak hari ini, dihitung dari log makan/minum pengguna hari ini.
    Wajib dipanggil sebelum menyarankan porsi atau menyebut sisa target."""
    user_id, session_factory = ctx(config)
    async with session_factory() as session:
        user = await session.get(User, user_id)
        mode = user.mode if user else "prevention"
        consumed = await logs_repo.today_totals(session, user_id)
    return {
        "mode": mode,
        "limits": DAILY_LIMITS,
        "consumed": asdict(consumed),
        "remaining": asdict(remaining_targets(consumed, mode)),
    }
