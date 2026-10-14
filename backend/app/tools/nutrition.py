from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool

from app.repos import foods as foods_repo
from app.tools._ctx import ctx


@tool
async def cari_gizi(makanan: str, config: RunnableConfig, porsi_gram: float | None = None) -> dict:
    """Ambil gula, natrium, lemak, dan kalori untuk makanan dan porsi tertentu dari database gizi KIRA.
    Wajib dipanggil sebelum menyebut angka gizi apa pun. Bila makanan tidak dikenal hasilnya
    {"found": false}: jangan mengarang angka, tanyakan makanannya ke pengguna."""
    _, session_factory = ctx(config)
    async with session_factory() as session:
        found = await foods_repo.lookup(session, makanan, porsi_gram)
    if found is None:
        return {"found": False}
    return {"found": True, **{k: v for k, v in found.items() if k != "food_id"}}
