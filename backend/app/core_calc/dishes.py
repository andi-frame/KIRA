"""Hidangan terkurasi: "ayam geprek" = ayam goreng tepung + nasi + sambal + timun, tiap komponen dihitung dari tabel foods.

Fungsi murni. Gram per komponen adalah asumsi KIRA (seed/dishes.json); angka gizi tetap dari tabel foods.
"""
from dataclasses import dataclass

from app.core_calc.foodindex import IndexEntry, best_match, build_index, normalize
from app.core_calc.nutrition import FoodRecord

# Typo pada nama hidangan ("ayam geperk") hanya diterima bila sangat mirip; selain itu abstain.
DISH_MIN_SCORE = 0.85
DISH_MARGIN = 0.1


@dataclass(frozen=True)
class DishComponent:
    food_id: str
    grams: float
    label: str | None = None


@dataclass(frozen=True)
class DishRecord:
    id: str
    name: str
    aliases: tuple[str, ...]
    serving_g: float
    components: tuple[DishComponent, ...]
    meal_kinds: tuple[str, ...] = ()
    source_note: str | None = None


@dataclass(frozen=True)
class ComponentPortion:
    food: FoodRecord
    grams: float
    label: str  # nama yang ditampilkan (label resep bila ada, selain itu nama makanan)


def _labels(dish: DishRecord) -> list[str]:
    return [normalize(dish.name), *(normalize(a) for a in dish.aliases)]


def match_dish(query: str, dishes: list[DishRecord]) -> DishRecord | None:
    """Cocokkan nama bebas ke hidangan. Urutan: nama/alias persis; label hidangan utuh terkandung di kueri
    ("ayam geprek level 5" -> ayam geprek, label terpanjang menang); lalu n-gram dengan ambang tinggi. Ragu -> None.

    Sengaja TIDAK mencocokkan kueri yang lebih pendek dari label ("nasi goreng" bukan "nasi goreng telur"):
    makanan tunggal di tabel foods harus tetap menang untuk kueri seperti itu.
    """
    needle = normalize(query)
    if not needle:
        return None
    for dish in dishes:
        if needle in _labels(dish):
            return dish
    words = set(needle.split())
    contained = [(len(label.split()), dish) for dish in dishes for label in _labels(dish) if set(label.split()) <= words]
    if contained:
        longest = max(n for n, _ in contained)
        tied = {d.id: d for n, d in contained if n == longest}
        return next(iter(tied.values())) if len(tied) == 1 else None
    if any(words < set(label.split()) for dish in dishes for label in _labels(dish)):
        return None  # kueri lebih pendek dari label hidangan ("rendang" vs "nasi rendang"): milik makanan tunggal
    index = build_index([IndexEntry(d.id, label, "dish") for d in dishes for label in _labels(d)])
    hit = best_match(needle, index, DISH_MIN_SCORE, DISH_MARGIN)
    return next(d for d in dishes if d.id == hit.key) if hit else None


def scale_for(dish: DishRecord, portion_g: float | None = None, servings: float | None = None) -> float:
    if portion_g is not None:
        if portion_g <= 0:
            raise ValueError(f"porsi harus lebih dari 0 gram: {portion_g}")
        return portion_g / dish.serving_g
    if servings is not None:
        if servings <= 0:
            raise ValueError(f"jumlah porsi harus lebih dari 0: {servings}")
        return servings
    return 1.0


def expand_dish(dish: DishRecord, foods: dict[str, FoodRecord], portion_g: float | None = None,
                servings: float | None = None) -> list[ComponentPortion]:
    """Komponen hidangan dengan gram yang diskalakan (portion_g / serving_g, atau jumlah porsi).
    Komponen yang food_id-nya tidak ada di tabel dilewati (tes seed menjaga hal ini tidak terjadi)."""
    scale = scale_for(dish, portion_g, servings)
    return [
        ComponentPortion(foods[c.food_id], c.grams * scale, c.label or foods[c.food_id].name)
        for c in dish.components if c.food_id in foods
    ]
