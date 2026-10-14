import re
from dataclasses import dataclass

from app.core_calc.constants import RED_FLAG_BP, RED_FLAG_GLUCOSE, RED_FLAG_KEYWORDS

_URGENT = (
    "Ini bisa jadi tanda bahaya. Segera ke IGD atau Puskesmas terdekat, "
    "atau minta seseorang menemanimu sekarang. KIRA tidak bisa menilai kondisi ini dari chat."
)


@dataclass(frozen=True)
class RedFlag:
    kind: str  # symptom | blood_pressure | glucose_high | glucose_low
    message: str


def detect_red_flags(
    text: str | None = None,
    glucose_mg_dl: float | None = None,
    bp: tuple[int, int] | None = None,
) -> RedFlag | None:
    if text:
        lowered = text.lower()
        if any(keyword in lowered for keyword in RED_FLAG_KEYWORDS):
            return RedFlag("symptom", _URGENT)
    if bp is not None and (bp[0] >= RED_FLAG_BP[0] or bp[1] >= RED_FLAG_BP[1]):
        return RedFlag("blood_pressure", f"Tekanan darah {bp[0]}/{bp[1]} sangat tinggi. {_URGENT}")
    if glucose_mg_dl is not None:
        if glucose_mg_dl <= RED_FLAG_GLUCOSE["low"]:
            return RedFlag("glucose_low", f"Gula darah {glucose_mg_dl:g} mg/dL sangat rendah. {_URGENT}")
        if glucose_mg_dl >= RED_FLAG_GLUCOSE["high"]:
            return RedFlag("glucose_high", f"Gula darah {glucose_mg_dl:g} mg/dL sangat tinggi. {_URGENT}")
    return None


_TIME = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")


def _minutes(value: str) -> int:
    match = _TIME.match(value)
    if not match:
        raise ValueError(f"format jam harus HH:MM: {value!r}")
    return int(match.group(1)) * 60 + int(match.group(2))


def parse_sleep_hours(bed_time: str, wake_time: str) -> float:
    bed, wake = _minutes(bed_time), _minutes(wake_time)
    minutes = wake - bed if wake > bed else wake + 24 * 60 - bed
    return minutes / 60
