"""Seed data statis (makanan lokal + faskes dummy). Idempoten: aman dijalankan berulang.

Pakai: python -m seed.load
"""
import asyncio
import json
from pathlib import Path

from sqlalchemy import text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

from app.config import settings
from app.models import Faskes, Food

SEED_DIR = Path(__file__).resolve().parent


def _food_rows() -> list[dict]:
    data = json.loads((SEED_DIR / "foods.json").read_text(encoding="utf-8"))
    rows = []
    for fid, name, aliases, sugar, sodium, fat, kcal, carb, portion in data["rows"]:
        rows.append(
            {
                "id": fid,
                "name": name,
                "aliases": [a.lower() for a in aliases],
                "per100g": {"sugar_g": sugar, "sodium_mg": sodium, "fat_g": fat, "kcal": kcal, "carb_g": carb},
                "default_portion_g": portion,
            }
        )
    return rows


async def load_seed(engine: AsyncEngine) -> None:
    faskes_rows = json.loads((SEED_DIR / "faskes.json").read_text(encoding="utf-8"))["rows"]
    async with engine.begin() as conn:
        await conn.execute(insert(Food).values(_food_rows()).on_conflict_do_nothing(index_elements=["id"]))
        existing = (await conn.execute(text("select count(*) from faskes"))).scalar_one()
        if existing == 0:
            await conn.execute(insert(Faskes).values(faskes_rows))


async def _main() -> None:
    engine = create_async_engine(settings.database_url)
    try:
        await load_seed(engine)
    finally:
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(_main())
