"""Rekaman makanan dan hidangan dari berkas seed sungguhan (tanpa basis data), untuk tes fungsi murni."""
from functools import cache

from app.core_calc.dishes import DishComponent, DishRecord
from app.core_calc.nutrition import FoodRecord
from seed.load import _component_rows, _dish_rows, _food_rows


@cache
def seed_foods() -> dict[str, FoodRecord]:
    return {
        r["id"]: FoodRecord(r["id"], r["name"], r["aliases"], r["per100g"], r["default_portion_g"], r["tkpi_code"],
                            r["source_note"])
        for r in _food_rows() + _component_rows()
    }


@cache
def seed_dishes() -> tuple[DishRecord, ...]:
    return tuple(
        DishRecord(d["id"], d["name"], tuple(d["aliases"]), d["serving_g"],
                   tuple(DishComponent(c["food_id"], c["grams"], c.get("label")) for c in d["components"]),
                   tuple(d["meal_kinds"]), d["source_note"])
        for d in _dish_rows()
    )
