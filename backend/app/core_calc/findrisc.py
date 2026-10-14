from dataclasses import dataclass
from typing import Literal

from app.core_calc.constants import (
    FINDRISC_CATEGORIES,
    FINDRISC_POINTS,
    P10_BY_CATEGORY,
)


@dataclass(frozen=True)
class FindriscInputs:
    age: int | None
    bmi: float | None
    sex: Literal["male", "female"] | None
    waist_cm: float | None
    active_30min: bool | None
    daily_veg_fruit: bool | None
    on_bp_medication: bool | None
    history_high_glucose: bool | None
    family_history: Literal["none", "second_degree", "first_degree"] | None


@dataclass(frozen=True)
class ScoreRange:
    low: int
    high: int


def _banded(value: float, spec: dict) -> int:
    for upper, points in spec["bands"]:
        if value < upper:
            return points
    return spec["top"]


def _all_banded(spec: dict) -> list[int]:
    return [p for _, p in spec["bands"]] + [spec["top"]]


def _bool_points(value: bool | None, yes_points: int, *, yes_means_points: bool) -> list[int]:
    """Poin yang mungkin. yes_means_points: True bila jawaban 'ya' yang memberi poin."""
    if value is None:
        return [0, yes_points]
    gives = value if yes_means_points else not value
    return [yes_points if gives else 0]


def _factor_options(i: FindriscInputs) -> list[list[int]]:
    p = FINDRISC_POINTS
    age = [_banded(i.age, p["age"])] if i.age is not None else _all_banded(p["age"])
    bmi = [_banded(i.bmi, p["bmi"])] if i.bmi is not None else _all_banded(p["bmi"])
    if i.sex is not None and i.waist_cm is not None:
        waist = [_banded(i.waist_cm, p["waist"][i.sex])]
    else:
        waist = sorted({q for s in ("male", "female") for q in _all_banded(p["waist"][s])})
    family = (
        [p["family_history"][i.family_history]]
        if i.family_history is not None
        else sorted(set(p["family_history"].values()))
    )
    return [
        age,
        bmi,
        waist,
        _bool_points(i.active_30min, p["activity_no"], yes_means_points=False),
        _bool_points(i.daily_veg_fruit, p["veg_fruit_no"], yes_means_points=False),
        _bool_points(i.on_bp_medication, p["bp_medication_yes"], yes_means_points=True),
        _bool_points(i.history_high_glucose, p["high_glucose_yes"], yes_means_points=True),
        family,
    ]


def score_range(inputs: FindriscInputs) -> ScoreRange:
    options = _factor_options(inputs)
    return ScoreRange(low=sum(min(o) for o in options), high=sum(max(o) for o in options))


def category(score: int) -> str:
    for lo, hi, label in FINDRISC_CATEGORIES:
        if lo <= score <= hi:
            return label
    raise ValueError(f"skor FINDRISC di luar 0-26: {score}")


def p10(score: int) -> float:
    return P10_BY_CATEGORY[category(score)]
