from dataclasses import dataclass
from typing import Literal

from app.core_calc.constants import DAILY_LIMITS, DAILY_LIMITS_MANAGEMENT


@dataclass(frozen=True)
class Totals:
    sugar_g: float
    sodium_mg: float
    fat_g: float


def remaining_targets(consumed: Totals, mode: Literal["prevention", "management"]) -> Totals:
    limits = DAILY_LIMITS_MANAGEMENT if mode == "management" else DAILY_LIMITS
    return Totals(
        sugar_g=max(0.0, limits["sugar_g"] - consumed.sugar_g),
        sodium_mg=max(0.0, limits["sodium_mg"] - consumed.sodium_mg),
        fat_g=max(0.0, limits["fat_g"] - consumed.fat_g),
    )
