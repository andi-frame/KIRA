import pytest

from app.core_calc.red_flags import RedFlag, detect_red_flags, parse_sleep_hours


def test_symptom_keyword_triggers():
    flag = detect_red_flags(text="Dada saya NYERI DADA sejak tadi")
    assert isinstance(flag, RedFlag) and flag.kind == "symptom"
    assert "IGD" in flag.message


def test_normal_text_does_not_trigger():
    assert detect_red_flags(text="tadi makan nasi padang rendang") is None


def test_very_high_bp_triggers():
    assert detect_red_flags(bp=(185, 110)).kind == "blood_pressure"
    assert detect_red_flags(bp=(150, 125)).kind == "blood_pressure"
    assert detect_red_flags(bp=(135, 85)) is None


def test_glucose_extremes_trigger():
    assert detect_red_flags(glucose_mg_dl=55).kind == "glucose_low"
    assert detect_red_flags(glucose_mg_dl=350).kind == "glucose_high"
    assert detect_red_flags(glucose_mg_dl=110) is None


def test_no_inputs_is_none():
    assert detect_red_flags() is None


@pytest.mark.parametrize(
    "bed,wake,hours", [("02:00", "07:00", 5.0), ("23:00", "06:00", 7.0), ("22:30", "05:00", 6.5)]
)
def test_sleep_hours_across_midnight(bed, wake, hours):
    assert parse_sleep_hours(bed, wake) == hours


def test_bad_time_format_raises():
    with pytest.raises(ValueError):
        parse_sleep_hours("25:00", "07:00")
