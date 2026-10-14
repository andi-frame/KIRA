from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool

from app.repos import faskes as faskes_repo
from app.tools._ctx import ctx


@tool
async def cari_faskes(lat: float, lng: float, config: RunnableConfig) -> dict:
    """Cari Posyandu/Puskesmas terdekat dari koordinat pengguna, terurut dari yang paling dekat."""
    _, session_factory = ctx(config)
    async with session_factory() as session:
        return {"faskes": await faskes_repo.nearby(session, lat, lng)}
