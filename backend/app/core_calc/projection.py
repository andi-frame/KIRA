from dataclasses import dataclass

from app.core_calc.findrisc import ScoreRange, p10

HORIZON_YEARS = 10


@dataclass(frozen=True)
class Band:
    low: list[float]
    high: list[float]


def cumulative_curve(p10_value: float, years: int = HORIZON_YEARS) -> list[float]:
    """Risiko kumulatif tahun 0..years dengan hazard konstan: R(t) = 1 - (1 - p10)^(t/10)."""
    return [1 - (1 - p10_value) ** (t / HORIZON_YEARS) for t in range(years + 1)]


def projection_band(rng: ScoreRange, years: int = HORIZON_YEARS) -> Band:
    return Band(
        low=cumulative_curve(p10(rng.low), years),
        high=cumulative_curve(p10(rng.high), years),
    )
