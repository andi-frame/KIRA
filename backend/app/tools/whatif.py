from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool

from app.services import risk
from app.services.projection_view import change_from_dict, whatif_payload
from app.tools._ctx import ctx


@tool
async def simulasi_whatif(perubahan: dict, config: RunnableConfig) -> dict:
    """Hitung ulang risiko bila kebiasaan digeser. `perubahan` boleh berisi: active_30min (true/false),
    daily_veg_fruit (true/false), weight_delta_kg (angka, negatif = turun), sweet_drinks_delta_per_day
    (angka, negatif = kurangi). Mengembalikan skor sebelum/sesudah dan dampak gula harian."""
    user_id, session_factory = ctx(config)
    async with session_factory() as session:
        state = await risk.compute_risk_state(session, user_id)
    return whatif_payload(state, change_from_dict(perubahan or {}))
