from app.core_calc.nutrition import FoodRecord, nutrition_for
from app.repos.logs import ItemData


def item_data(name: str, food: FoodRecord | None, grams: float | None, multiplier: float = 1.0) -> ItemData:
    """Baris log_items dengan gizi dari tabel pangan; tanpa kecocokan, hanya nama + porsi."""
    if food is None:
        return ItemData(name=name, portion_g=grams)
    n = nutrition_for(food, grams)
    return ItemData(
        name=name, portion_g=n["portion_g"] * multiplier, sugar_g=n["sugar_g"] * multiplier,
        sodium_mg=n["sodium_mg"] * multiplier, fat_g=n["fat_g"] * multiplier,
        kcal=n["kcal"] * multiplier, food_id=food.id,
    )
