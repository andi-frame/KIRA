import pytest

from app.core_calc.bp import bp_category, validate_glucose


@pytest.mark.parametrize(
    "sys_,dia,expected",
    [(118, 76, "normal"), (130, 85, "prehypertension"), (150, 95, "hypertension"),
     (119, 90, "hypertension"), (140, 70, "hypertension"), (110, 80, "normal"),
     (129, 84, "normal"), (130, 70, "prehypertension"), (120, 85, "prehypertension"),
     (139, 89, "prehypertension"), (140, 89, "hypertension")],
)
def test_bp_categories(sys_, dia, expected):
    assert bp_category(sys_, dia) == expected


@pytest.mark.parametrize("sys_,dia", [(400, 80), (120, 130), (40, 30), (120, 20)])
def test_implausible_bp_rejected(sys_, dia):
    with pytest.raises(ValueError):
        bp_category(sys_, dia)


@pytest.mark.parametrize("value", [5, 19.9, 800.1, 5000])
def test_implausible_glucose_rejected(value):
    with pytest.raises(ValueError):
        validate_glucose(value)


def test_plausible_glucose_returned():
    assert validate_glucose(110) == 110
