import pytest

from app.core_calc.findrisc import ScoreRange, p10
from app.core_calc.projection import Band, cumulative_curve, projection_band


def test_curve_starts_at_zero_ends_at_p10_and_rises():
    curve = cumulative_curve(0.17)
    assert len(curve) == 11
    assert curve[0] == 0.0
    assert curve[-1] == pytest.approx(0.17)
    assert curve == sorted(curve)


def test_curve_follows_constant_hazard_formula():
    curve = cumulative_curve(0.33)
    assert curve[5] == pytest.approx(1 - (1 - 0.33) ** 0.5)


def test_band_low_never_exceeds_high():
    band = projection_band(ScoreRange(6, 18))
    assert isinstance(band, Band)
    assert all(lo <= hi for lo, hi in zip(band.low, band.high))
    assert band.high[-1] == pytest.approx(p10(18))
    assert band.low[-1] == pytest.approx(p10(6))
