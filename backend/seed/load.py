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
from app.models import Dish, Faskes, Food

SEED_DIR = Path(__file__).resolve().parent


def _tkpi() -> dict:
    return json.loads((SEED_DIR / "tkpi_2017.json").read_text(encoding="utf-8"))["foods"]


def _food_rows() -> list[dict]:
    """Gabungkan seed estimasi dengan TKPI Kemenkes 2017 (sumber primer) bila ada padanannya.

    TKPI tidak memuat gula, jadi gula SELALU estimasi; natrium estimasi bila TKPI tidak menyediakannya.
    Porsi khas (default_portion_g) juga estimasi KIRA.
    """
    data = json.loads((SEED_DIR / "foods.json").read_text(encoding="utf-8"))
    tkpi = _tkpi()
    rows = []
    for fid, name, aliases, sugar, sodium, fat, kcal, carb, portion in data["rows"]:
        per100g = {"sugar_g": sugar, "sodium_mg": sodium, "fat_g": fat, "kcal": kcal, "carb_g": carb}
        ref = tkpi.get(fid)
        if ref is None:
            note = "Estimasi KIRA (belum ada padanan di TKPI): semua nilai estimasi; gula: estimasi; porsi: estimasi"
            code = None
        else:
            per100g.update(kcal=ref["kcal"], fat_g=ref["fat_g"] if ref["fat_g"] is not None else fat,
                           carb_g=ref["carb_g"] if ref["carb_g"] is not None else carb)
            parts = ["energi, lemak, karbohidrat" + (", natrium" if ref["sodium_mg"] is not None else "")]
            if ref["sodium_mg"] is not None:
                per100g["sodium_mg"] = ref["sodium_mg"]
            note = f"TKPI Kemenkes 2017 ({ref['code']}): {parts[0]}"
            if ref["sodium_mg"] is None:
                note += "; natrium: estimasi"
            note += "; gula: estimasi; porsi: estimasi"
            code = ref["code"]
        rows.append(
            {
                "id": fid,
                "name": name,
                "aliases": [a.lower() for a in aliases],
                "per100g": per100g,
                "default_portion_g": portion,
                "tkpi_code": code,
                "source_note": note,
            }
        )
    return rows


def _component_rows() -> list[dict]:
    """Bahan/komponen sederhana (timun, sambal, ayam goreng tepung, ...) dari components.json, dibuat oleh
    seed/fetch_components.py. Nilainya sudah final per 100 g; asal tiap angka ada di source_note."""
    data = json.loads((SEED_DIR / "components.json").read_text(encoding="utf-8"))
    rows = []
    for fid, name, aliases, sugar, sodium, fat, kcal, carb, portion, source, note in data["rows"]:
        rows.append({
            "id": fid, "name": name, "aliases": [a.lower() for a in aliases],
            "per100g": {"sugar_g": sugar, "sodium_mg": sodium, "fat_g": fat, "kcal": kcal, "carb_g": carb},
            "default_portion_g": portion, "tkpi_code": source.split(":", 1)[1] if source.startswith("TKPI:") else None,
            "source_note": note,
        })
    return rows


def _dish_rows() -> list[dict]:
    data = json.loads((SEED_DIR / "dishes.json").read_text(encoding="utf-8"))
    return [{**d, "aliases": [a.lower() for a in d["aliases"]]} for d in data["dishes"]]


async def load_seed(engine: AsyncEngine) -> None:
    faskes_rows = json.loads((SEED_DIR / "faskes.json").read_text(encoding="utf-8"))["rows"]
    async with engine.begin() as conn:
        stmt = insert(Food).values(_food_rows() + _component_rows())
        await conn.execute(
            stmt.on_conflict_do_update(
                index_elements=["id"],
                set_={c: getattr(stmt.excluded, c) for c in ("name", "aliases", "per100g", "default_portion_g",
                                                              "tkpi_code", "source_note")},
            )
        )
        stmt = insert(Dish).values(_dish_rows())
        await conn.execute(
            stmt.on_conflict_do_update(
                index_elements=["id"],
                set_={c: getattr(stmt.excluded, c) for c in ("name", "aliases", "serving_g", "meal_kinds",
                                                              "components", "source_note")},
            )
        )
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
