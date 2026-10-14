from dataclasses import dataclass
from typing import Literal

from app.core_calc.constants import DAILY_LIMITS, MANAGEMENT_STRICTNESS


@dataclass(frozen=True)
class Totals:
    sugar_g: float
    sodium_mg: float
    fat_g: float


def remaining_targets(consumed: Totals, mode: Literal["prevention", "management"]) -> Totals:
    factor = MANAGEMENT_STRICTNESS if mode == "management" else 1.0
    return Totals(
        sugar_g=max(0.0, DAILY_LIMITS["sugar_g"] * factor - consumed.sugar_g),
        sodium_mg=max(0.0, DAILY_LIMITS["sodium_mg"] * factor - consumed.sodium_mg),
        fat_g=max(0.0, DAILY_LIMITS["fat_g"] * factor - consumed.fat_g),
    )
