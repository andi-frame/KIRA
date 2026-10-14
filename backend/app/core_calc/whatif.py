from dataclasses import dataclass, replace

from app.core_calc.findrisc import FindriscInputs, ScoreRange, score_range


@dataclass(frozen=True)
class WhatIfChange:
    active_30min: bool | None = None
    daily_veg_fruit: bool | None = None
    weight_delta_kg: float | None = None
    sweet_drinks_delta_per_day: float = 0.0


@dataclass(frozen=True)
class WhatIfResult:
    before: ScoreRange
    after: ScoreRange
    sugar_g_before: float
    sugar_g_after: float
    most_impactful: str  # activity | veg_fruit | weight | sweet_drinks | none


def _apply(
    inputs: FindriscInputs,
    height_cm: float | None,
    weight_kg: float | None,
    change: WhatIfChange,
) -> FindriscInputs:
    updated = inputs
    if change.active_30min is not None:
        updated = replace(updated, active_30min=change.active_30min)
    if change.daily_veg_fruit is not None:
        updated = replace(updated, daily_veg_fruit=change.daily_veg_fruit)
    if change.weight_delta_kg is not None and height_cm and weight_kg:
        new_bmi = (weight_kg + change.weight_delta_kg) / (height_cm / 100) ** 2
        updated = replace(updated, bmi=round(new_bmi, 1))
    return updated


def _single_changes(change: WhatIfChange) -> dict[str, WhatIfChange]:
    singles: dict[str, WhatIfChange] = {}
    if change.active_30min is not None:
        singles["activity"] = WhatIfChange(active_30min=change.active_30min)
    if change.daily_veg_fruit is not None:
        singles["veg_fruit"] = WhatIfChange(daily_veg_fruit=change.daily_veg_fruit)
    if change.weight_delta_kg is not None:
        singles["weight"] = WhatIfChange(weight_delta_kg=change.weight_delta_kg)
    if change.sweet_drinks_delta_per_day:
        singles["sweet_drinks"] = WhatIfChange(
            sweet_drinks_delta_per_day=change.sweet_drinks_delta_per_day
        )
    return singles


def simulate(
    inputs: FindriscInputs,
    height_cm: float | None,
    weight_kg: float | None,
    change: WhatIfChange,
    avg_sweet_drinks_per_day: float,
    sugar_g_per_drink: float,
) -> WhatIfResult:
    before = score_range(inputs)
    after = score_range(_apply(inputs, height_cm, weight_kg, change))

    def sugar(delta: float) -> float:
        return max(0.0, (avg_sweet_drinks_per_day + delta) * sugar_g_per_drink)

    sugar_before = sugar(0.0)
    best, best_key = "none", (0, 0.0)
    for name, single in _single_changes(change).items():
        single_after = score_range(_apply(inputs, height_cm, weight_kg, single))
        key = (before.high - single_after.high, sugar_before - sugar(single.sweet_drinks_delta_per_day))
        if key > best_key or best == "none":
            best, best_key = name, key
    return WhatIfResult(
        before=before,
        after=after,
        sugar_g_before=sugar_before,
        sugar_g_after=sugar(change.sweet_drinks_delta_per_day),
        most_impactful=best,
    )
