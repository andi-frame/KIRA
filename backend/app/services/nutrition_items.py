"""Dari nama makanan (dan petunjuk model) ke baris log_items bergizi. Angka gizi selalu dari tabel foods.

Urutan untuk satu FoodItem (docs/spesifikasi-beranda-perencana.md 3.3):
1. dish_id dari katalog, atau nama cocok dengan hidangan terkurasi -> dipecah menjadi komponen (group_name = hidangan);
2. food_id dari katalog, atau nama cocok dengan makanan (match_food) -> satu item;
3. komponen dari model -> tiap komponen lewat food_id valid / match_food / indeks n-gram;
4. indeks n-gram terhadap nama (salah ketik yang jelas);
5. tidak ada yang meyakinkan -> abstain: hanya nama + porsi, dengan catatan "belum ada di database gizi".
id yang tidak ada di katalog dibuang (model tidak boleh mengarang id).
"""
from dataclasses import dataclass, field

from app.core_calc.dishes import DishRecord, expand_dish, match_dish, match_dish_exact
from app.core_calc.foodindex import FoodIndex, IndexEntry, best_match, build_index
from app.core_calc.nutrition import FoodRecord, match_food, nutrition_for
from app.repos.logs import ItemData
from app.schemas.extraction import FoodItem


@dataclass(frozen=True)
class FoodCatalog:
    foods: tuple[FoodRecord, ...]
    dishes: tuple[DishRecord, ...] = ()
    by_id: dict[str, FoodRecord] = field(default_factory=dict)
    dishes_by_id: dict[str, DishRecord] = field(default_factory=dict)
    index: FoodIndex | None = None

    @classmethod
    def build(cls, foods: list[FoodRecord], dishes: list[DishRecord] | None = None) -> "FoodCatalog":
        dishes = dishes or []
        index = build_index([IndexEntry(f.id, label) for f in foods for label in [f.name, *f.aliases]])
        return cls(tuple(foods), tuple(dishes), {f.id: f for f in foods}, {d.id: d for d in dishes}, index)

    def find_food(self, name: str, food_id: str | None = None) -> FoodRecord | None:
        if food_id and food_id in self.by_id:
            return self.by_id[food_id]
        found = match_food(name, list(self.foods))
        if found is None and self.index is not None:
            hit = best_match(name, self.index)
            found = self.by_id.get(hit.key) if hit else None
        return found

    def exact_food(self, name: str, food_id: str | None = None) -> FoodRecord | None:
        """Hanya id katalog atau nama/alias persis (tanpa fuzzy)."""
        if food_id and food_id in self.by_id:
            return self.by_id[food_id]
        needle = name.strip().lower()
        return next((f for f in self.foods if needle in [f.name.lower(), *(a.lower() for a in f.aliases)]), None)

    def find_dish(self, name: str, dish_id: str | None = None, *, exact_only: bool = False) -> DishRecord | None:
        """`exact_only`: model sudah memecah makanan ini menjadi komponen, jadi hanya nama persis yang boleh menimpanya."""
        if dish_id and dish_id in self.dishes_by_id:
            return self.dishes_by_id[dish_id]
        return match_dish_exact(name, list(self.dishes)) if exact_only else match_dish(name, list(self.dishes))


def item_data(name: str, food: FoodRecord | None, grams: float | None, multiplier: float = 1.0,
              group_name: str | None = None) -> ItemData:
    """Baris log_items dengan gizi dari tabel pangan; tanpa kecocokan, hanya nama + porsi."""
    if food is None:
        return ItemData(name=name, portion_g=grams, group_name=group_name)
    n = nutrition_for(food, grams)
    return ItemData(
        name=name, portion_g=n["portion_g"] * multiplier, sugar_g=n["sugar_g"] * multiplier,
        sodium_mg=n["sodium_mg"] * multiplier, fat_g=n["fat_g"] * multiplier,
        kcal=n["kcal"] * multiplier, food_id=food.id, group_name=group_name,
    )


@dataclass
class Resolution:
    items: list[ItemData]
    notes: list[str]
    trace: dict  # disimpan di logs.extracted["resolved"]: dari mana komponen berasal (untuk jejak dan koreksi)


def _unknown(name: str) -> str:
    return f"Makanan '{name}' belum ada di database gizi; gizinya belum terhitung."


def resolve_food_item(item: FoodItem, catalog: FoodCatalog) -> Resolution:
    dish = catalog.find_dish(item.name, item.dish_id, exact_only=bool(item.components))
    if dish is not None:
        parts = expand_dish(dish, catalog.by_id, portion_g=item.portion_g_guess)
        items = [item_data(p.label, p.food, p.grams, group_name=dish.name) for p in parts]
        return Resolution(items, [], {"name": item.name, "dish_id": dish.id,
                                      "components": [{"food_id": p.food.id, "grams": round(p.grams, 1)} for p in parts]})

    # Bila model sudah memecah hidangan, hanya kecocokan persis yang boleh menimpanya: fuzzy bisa menarik
    # "ayam bakar madu" ke "ayam bakar" dan membuang komponennya.
    food = (catalog.exact_food(item.name, item.food_id) if item.components
            else catalog.find_food(item.name, item.food_id))
    if food is not None:
        return Resolution([item_data(item.name, food, item.portion_g_guess)], [],
                          {"name": item.name, "food_id": food.id})

    if item.components:
        items, notes, used = [], [], []
        for comp in item.components:
            comp_food = catalog.find_food(comp.name, comp.food_id)
            if comp_food is None:
                notes.append(f"Komponen '{comp.name}' dari '{item.name}' belum ada di database gizi; gizinya belum terhitung.")
            items.append(item_data(comp.name, comp_food, comp.portion_g_guess, group_name=item.name))
            used.append({"name": comp.name, "food_id": comp_food.id if comp_food else None})
        return Resolution(items, notes, {"name": item.name, "components": used, "from_model": True})

    return Resolution([item_data(item.name, None, item.portion_g_guess)], [_unknown(item.name)],
                      {"name": item.name, "food_id": None})
