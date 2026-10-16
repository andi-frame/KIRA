from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool

from app.services import faskes_lookup
from app.tools._ctx import ctx


@tool
async def cari_faskes(lat: float, lng: float, config: RunnableConfig) -> dict:
    """Cari Puskesmas, klinik, atau rumah sakit terdekat dari koordinat pengguna (data peta), terurut dari yang paling dekat."""
    _, session_factory = ctx(config)
    async with session_factory() as session:
        found = await faskes_lookup.nearby(session, lat, lng)
        return {"faskes": found["faskes"][:5], "sumber": found["source"]}
