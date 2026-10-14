from typing import Literal

from app.core_calc.constants import BP_THRESHOLDS

BpCategory = Literal["normal", "prehypertension", "hypertension"]

SYS_RANGE = (50, 300)
DIA_RANGE = (30, 200)
GLUCOSE_RANGE = (20.0, 800.0)  # mg/dL, batas kemungkinan terukur


def bp_category(sys: int, dia: int) -> BpCategory:
    if not (SYS_RANGE[0] <= sys <= SYS_RANGE[1]) or not (DIA_RANGE[0] <= dia <= DIA_RANGE[1]):
        raise ValueError(f"tekanan darah tidak masuk akal: {sys}/{dia}")
    if dia >= sys:
        raise ValueError(f"diastolik harus lebih kecil dari sistolik: {sys}/{dia}")
    for label in ("hypertension", "prehypertension"):
        sys_min, dia_min = BP_THRESHOLDS[label]
        if sys >= sys_min or dia >= dia_min:
            return label  # type: ignore[return-value]
    return "normal"


def validate_glucose(mg_dl: float) -> float:
    if not (GLUCOSE_RANGE[0] <= mg_dl <= GLUCOSE_RANGE[1]):
        raise ValueError(f"gula darah tidak masuk akal: {mg_dl}")
    return mg_dl
