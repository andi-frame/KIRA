from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool

from app.core_calc.dishes import expand_dish
from app.core_calc.nutrition import nutrition_for
from app.repos import foods as foods_repo
from app.tools._ctx import ctx

_KEYS = ("sugar_g", "sodium_mg", "fat_g", "kcal")


@tool
async def cari_gizi(makanan: str, config: RunnableConfig, porsi_gram: float | None = None) -> dict:
    """Ambil gula, natrium, lemak, dan kalori untuk makanan dan porsi tertentu dari database gizi KIRA.
    Wajib dipanggil sebelum menyebut angka gizi apa pun. Field `sumber` menyebut asal angka; bila memuat "estimasi", sebut angkanya sebagai perkiraan. Bila makanan tidak dikenal hasilnya
    {"found": false}: jangan mengarang angka, tanyakan makanannya ke pengguna.
    Untuk hidangan campuran (mis. ayam geprek) hasilnya memuat `hidangan`, `komponen` (gizi tiap komponen), dan `total`;
    gram komponen adalah perkiraan resep, sampaikan sebagai perkiraan."""
    _, session_factory = ctx(config)
    async with session_factory() as session:
        catalog = await foods_repo.catalog(session)
    dish = catalog.find_dish(makanan)
    if dish is not None:
        komponen = []
        for part in expand_dish(dish, catalog.by_id, portion_g=porsi_gram):
            n = nutrition_for(part.food, part.grams)
            komponen.append({"nama": part.label, "gram": round(part.grams, 1),
                             **{k: round(n[k], 1) for k in _KEYS}, "sumber": part.food.source_note or "Estimasi KIRA"})
        total = {k: round(sum(c[k] for c in komponen), 1) for k in _KEYS}
        return {"found": True, "hidangan": dish.name, "porsi_g": round(sum(c["gram"] for c in komponen), 1),
                "komponen": komponen, "total": total, "sumber": f"Komponen dari tabel gizi; {dish.source_note}"}
    food = catalog.find_food(makanan)
    if food is None:
        return {"found": False}
    return {"found": True, "sumber": food.source_note or "Estimasi KIRA", "name": food.name,
            **nutrition_for(food, porsi_gram)}
