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


@pytest.mark.parametrize(
    "text",
    [
        "sakit dada dari tadi",
        "dadaku nyeri banget",
        "nyeri di dada kiri",
        "napas sesak sejak pagi",
        "susah napas pas naik tangga",
        "sulit nafas",
        "tangan kiri mati rasa, mulut mencong",
        "tiba-tiba bicara pelo",
        "tadi sempat pingsan",
        "tensi saya 200/130 dan pusing",
        "tekanan darah 190/115",
        "gula darah 450",
        "gds saya 38 lemas",
    ],
)
def test_common_indonesian_phrasings_of_danger_are_caught(text):
    assert detect_red_flags(text=text) is not None, text


@pytest.mark.parametrize(
    "text",
    [
        "tadi makan dada ayam goreng",
        "sakit perut habis makan dada ayam",
        "gula 20 gram di kopi",
        "tensi saya 120/80",
        "gula darah 110",
        "tanggal 12/10 aku tidur jam 11",
        "gula 5000",
    ],
)
def test_ordinary_text_is_not_flagged(text):
    assert detect_red_flags(text=text) is None, text


def test_glucose_boundaries_follow_perkeni():
    assert detect_red_flags(glucose_mg_dl=70) is None  # hipoglikemia = di bawah 70
    assert detect_red_flags(glucose_mg_dl=69).kind == "glucose_low"
    assert detect_red_flags(glucose_mg_dl=299) is None
    assert detect_red_flags(glucose_mg_dl=300).kind == "glucose_high"


def test_bp_boundaries_follow_kemenkes_grade_3():
    assert detect_red_flags(bp=(179, 109)) is None
    assert detect_red_flags(bp=(180, 100)).kind == "blood_pressure"
    assert detect_red_flags(bp=(150, 110)).kind == "blood_pressure"
