from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.dishes import DishComponent, DishRecord, match_dish
from app.core_calc.foodindex import IndexEntry, build_index
from app.core_calc.foodindex import search as index_search
from app.core_calc.nutrition import FoodRecord, match_food, nutrition_for
from app.models import Dish, Food


async def all_foods(session: AsyncSession) -> list[FoodRecord]:
    rows = (await session.execute(select(Food).order_by(Food.id))).scalars().all()
    return [
        FoodRecord(r.id, r.name, list(r.aliases or []), dict(r.per100g), float(r.default_portion_g or 100),
                   r.tkpi_code, r.source_note)
        for r in rows
    ]


async def all_dishes(session: AsyncSession) -> list[DishRecord]:
    rows = (await session.execute(select(Dish).order_by(Dish.id))).scalars().all()
    return [
        DishRecord(r.id, r.name, tuple(r.aliases or []), float(r.serving_g),
                   tuple(DishComponent(c["food_id"], float(c["grams"]), c.get("label")) for c in r.components),
                   tuple(r.meal_kinds or []), r.source_note)
        for r in rows
    ]


async def catalog(session: AsyncSession):
    from app.services.nutrition_items import FoodCatalog  # hindari impor melingkar (services -> repos)

    return FoodCatalog.build(await all_foods(session), await all_dishes(session))


def catalog_prompt(cat) -> str:
    """Katalog ringkas untuk ekstraksi: model memetakan nama ke id, tidak pernah mengisi angka gizi."""
    foods = "\n".join(f"{f.id}|{f.name}" for f in cat.foods)
    dishes = "\n".join(
        f"{d.id}|{d.name}: " + ", ".join(cat.by_id[c.food_id].name.lower() for c in d.components if c.food_id in cat.by_id)
        for d in cat.dishes
    )
    return f"KATALOG MAKANAN (food_id|nama):\n{foods}\n\nKATALOG HIDANGAN (dish_id|nama: komponen):\n{dishes}"


async def lookup(session: AsyncSession, name: str, grams: float | None = None) -> dict | None:
    """Cocokkan nama ke tabel gizi; None bila tidak dikenal."""
    food = (await catalog(session)).find_food(name)
    if food is None:
        return None
    return {"food_id": food.id, "name": food.name, "source_note": food.source_note, **nutrition_for(food, grams)}


async def search(session: AsyncSession, query: str, limit: int = 8) -> list[dict]:
    """Saran untuk UI koreksi: gabungan nama persis/alias (makanan dan hidangan) lalu indeks n-gram."""
    cat = await catalog(session)
    out: list[dict] = []
    seen: set[tuple[str, str]] = set()

    def add(kind: str, key: str, name: str, score: float, portion_g: float) -> None:
        if (kind, key) not in seen and len(out) < limit:
            seen.add((kind, key))
            out.append({"kind": kind, "id": key, "name": name, "score": round(score, 3), "portion_g": portion_g})

    dish = match_dish(query, list(cat.dishes))
    if dish:
        add("dish", dish.id, dish.name, 1.0, dish.serving_g)
    food = match_food(query, list(cat.foods))
    if food:
        add("food", food.id, food.name, 1.0, food.default_portion_g)
    dish_index = build_index([IndexEntry(d.id, label, "dish") for d in cat.dishes for label in [d.name, *d.aliases]])
    hits = index_search(query, cat.index, top_k=limit, min_score=0.3) + index_search(query, dish_index, top_k=limit,
                                                                                      min_score=0.3)
    for hit in sorted(hits, key=lambda h: (-h.score, h.key)):
        if hit.kind == "dish":
            d = cat.dishes_by_id[hit.key]
            add("dish", d.id, d.name, hit.score, d.serving_g)
        else:
            f = cat.by_id[hit.key]
            add("food", f.id, f.name, hit.score, f.default_portion_g)
    return out
