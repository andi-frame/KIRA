"""Gizi dari tabel informasi nilai gizi di kemasan (angka tercetak di label, bukan estimasi).

Fungsi murni. Nilai yang mustahil secara fisik (gula melebihi berat sajian, kalori di atas batas lemak murni)
ditolak dengan ValueError: itu hampir pasti salah baca foto, dan lebih baik tidak disimpan.
"""
from dataclasses import dataclass
from typing import Literal

NUTRIENTS = ("sugar_g", "sodium_mg", "fat_g", "kcal")
MAX_SERVINGS = 50
MAX_KCAL_PER_G = 9.0  # lemak murni sekitar 9 kkal/g; tidak ada pangan di atasnya
MAX_SODIUM_MG_PER_G = 400.0  # garam dapur sekitar 39% natrium berat; tidak ada pangan di atasnya
PER_SERVING_TOLERANCE = 1.1  # pembulatan angka dan takaran saji di label; label per 100 g harus tepat


@dataclass(frozen=True)
class LabelFacts:
    basis: Literal["per_serving", "per_100g"]
    serving_g: float | None
    servings_consumed: float = 1.0
    sugar_g: float | None = None
    sodium_mg: float | None = None
    fat_g: float | None = None
    kcal: float | None = None


def _validate(f: LabelFacts) -> None:
    if not 0 < f.servings_consumed <= MAX_SERVINGS:
        raise ValueError(f"jumlah sajian tidak masuk akal: {f.servings_consumed}")
    if f.serving_g is not None and f.serving_g <= 0:
        raise ValueError(f"takaran saji harus lebih dari 0: {f.serving_g}")
    values = {name: getattr(f, name) for name in NUTRIENTS}
    if any(v is not None and v < 0 for v in values.values()):
        raise ValueError("nilai gizi tidak boleh negatif")
    # Dasar perbandingan dalam gram: 100 g untuk label per 100 g, satu sajian untuk label per sajian.
    base_g = 100.0 if f.basis == "per_100g" else f.serving_g
    if base_g is None:
        return
    base_g *= 1.0 if f.basis == "per_100g" else PER_SERVING_TOLERANCE
    if values["sugar_g"] is not None and values["sugar_g"] > base_g:
        raise ValueError("gula melebihi berat sajian")
    if values["fat_g"] is not None and values["fat_g"] > base_g:
        raise ValueError("lemak melebihi berat sajian")
    if values["kcal"] is not None and values["kcal"] > base_g * MAX_KCAL_PER_G:
        raise ValueError("kalori melebihi batas fisik")
    if values["sodium_mg"] is not None and values["sodium_mg"] > base_g * MAX_SODIUM_MG_PER_G:
        raise ValueError("natrium melebihi batas fisik")


def label_totals(f: LabelFacts) -> dict[str, float | None] | None:
    """Total yang dikonsumsi: gram porsi dan gizi. Zat yang tidak tertera di label tetap None (bukan 0).
    Mengembalikan None bila label per 100 g tetapi takaran sajian tidak diketahui (porsi tidak bisa dihitung)."""
    _validate(f)
    if f.basis == "per_100g":
        if f.serving_g is None:
            return None
        grams = f.serving_g * f.servings_consumed
        scale = grams / 100
        portion: float | None = grams
    else:
        scale = f.servings_consumed
        portion = f.serving_g * f.servings_consumed if f.serving_g is not None else None
    totals: dict[str, float | None] = {"portion_g": portion}
    for name in NUTRIENTS:
        value = getattr(f, name)
        totals[name] = None if value is None else value * scale
    return totals
