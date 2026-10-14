from dataclasses import dataclass
from typing import Literal

from app.core_calc.findrisc import ScoreRange, category


@dataclass(frozen=True)
class CheckRecommendation:
    test_kind: Literal["fasting_glucose", "blood_pressure"]
    reason: str


_GLUCOSE_REASON = (
    "Proyeksimu masih punya rentang lebar karena gula darahmu belum pernah diukur. "
    "Cek gula darah puasa adalah langkah yang paling mempersempit perkiraan ini."
)
_BP_REASON_AFTER_TRIGGER = (
    "Perkiraanmu masih belum pasti dan tensimu belum diketahui. "
    "Cek tensi di Posyandu atau Puskesmas akan membantu memperjelas gambarnya."
)
_BP_REASON_UNMEASURED = (
    "Tensimu belum pernah tercatat. Cek tensi itu cepat dan gratis di Posyandu atau Puskesmas."
)


def evaluate_check(
    rng: ScoreRange,
    glucose_known: bool,
    bp_known: bool,
    habits_worsening: bool,
) -> CheckRecommendation | None:
    triggered = (
        category(rng.low) != category(rng.high)
        or category(rng.high) in {"high", "very_high"}
        or habits_worsening
    )
    if triggered:
        if not glucose_known:
            return CheckRecommendation("fasting_glucose", _GLUCOSE_REASON)
        if not bp_known:
            return CheckRecommendation("blood_pressure", _BP_REASON_AFTER_TRIGGER)
        return None
    if not bp_known:
        return CheckRecommendation("blood_pressure", _BP_REASON_UNMEASURED)
    return None
