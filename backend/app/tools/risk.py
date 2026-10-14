from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool

from app.services import risk
from app.services.projection_view import projection_payload
from app.tools._ctx import ctx


@tool
async def hitung_risiko(config: RunnableConfig) -> dict:
    """Hitung rentang skor risiko diabetes 10 tahun (FINDRISC) dan kategori tekanan darah terakhir dari profil
    dan log pengguna. Hasilnya berupa RENTANG, sampaikan sebagai rentang. Wajib dipanggil sebelum menyebut
    angka atau kategori risiko. Bila needs_profile=true, ajak pengguna melengkapi profil."""
    user_id, session_factory = ctx(config)
    async with session_factory() as session:
        state = await risk.compute_risk_state(session, user_id)
    return projection_payload(state)
