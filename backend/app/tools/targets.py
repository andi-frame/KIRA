from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool

from app.services.targets_view import today_targets
from app.tools._ctx import ctx


@tool
async def sisa_target_harian(config: RunnableConfig) -> dict:
    """Sisa batas gula, garam (natrium), dan lemak hari ini, dihitung dari log makan/minum pengguna hari ini.
    Wajib dipanggil sebelum menyarankan porsi atau menyebut sisa target."""
    user_id, session_factory = ctx(config)
    async with session_factory() as session:
        return await today_targets(session, user_id)
