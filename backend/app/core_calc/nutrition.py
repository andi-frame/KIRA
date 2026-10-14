import difflib
from dataclasses import dataclass

_FUZZY_CUTOFF = 0.8


@dataclass(frozen=True)
class FoodRecord:
    id: str
    name: str
    aliases: list[str]
    per100g: dict[str, float]  # sugar_g, sodium_mg, fat_g, kcal, carb_g
    default_portion_g: float


def match_food(query: str, foods: list[FoodRecord]) -> FoodRecord | None:
    needle = query.strip().lower()
    if not needle:
        return None
    index: dict[str, FoodRecord] = {}
    for food in foods:
        for label in [food.name, *food.aliases]:
            index.setdefault(label.lower(), food)
    if needle in index:
        return index[needle]
    # Semua kata kueri ada di sebuah label ("rendang" -> "rendang sapi"). Ambil label terpendek;
    # bila beberapa makanan berbeda seri, ambigu -> None (jangan menebak).
    words = set(needle.split())
    containing = [(label, food) for label, food in index.items() if words <= set(label.split())]
    if containing:
        fewest = min(len(label.split()) for label, _ in containing)
        tied = {food.id: food for label, food in containing if len(label.split()) == fewest}
        return next(iter(tied.values())) if len(tied) == 1 else None
    close = difflib.get_close_matches(needle, list(index), n=1, cutoff=_FUZZY_CUTOFF)
    return index[close[0]] if close else None


def nutrition_for(food: FoodRecord, grams: float | None) -> dict[str, float]:
    portion = food.default_portion_g if grams is None else grams
    if portion <= 0:
        raise ValueError(f"porsi harus lebih dari 0 gram: {portion}")
    scale = portion / 100
    return {
        "portion_g": portion,
        "sugar_g": food.per100g["sugar_g"] * scale,
        "sodium_mg": food.per100g["sodium_mg"] * scale,
        "fat_g": food.per100g["fat_g"] * scale,
        "kcal": food.per100g["kcal"] * scale,
    }
