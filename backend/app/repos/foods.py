from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.nutrition import FoodRecord, match_food, nutrition_for
from app.models import Food


async def all_foods(session: AsyncSession) -> list[FoodRecord]:
    rows = (await session.execute(select(Food))).scalars().all()
    return [
        FoodRecord(r.id, r.name, list(r.aliases or []), dict(r.per100g), float(r.default_portion_g or 100),
                   r.tkpi_code, r.source_note)
        for r in rows
    ]


async def lookup(session: AsyncSession, name: str, grams: float | None = None) -> dict | None:
    """Cocokkan nama ke tabel gizi; None bila tidak dikenal."""
    food = match_food(name, await all_foods(session))
    if food is None:
        return None
    return {"food_id": food.id, "name": food.name, "source_note": food.source_note, **nutrition_for(food, grams)}
