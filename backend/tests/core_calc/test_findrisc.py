import pytest

from app.core_calc.findrisc import FindriscInputs, ScoreRange, category, p10, score_range

FULL = dict(
    age=28, bmi=27.0, sex="male", waist_cm=95.0, active_30min=True, daily_veg_fruit=True,
    on_bp_medication=False, history_high_glucose=False, family_history="first_degree",
)


def test_full_profile_gives_exact_score_and_category():
    rng = score_range(FindriscInputs(**FULL))
    assert rng == ScoreRange(9, 9)
    assert category(9) == "slightly_elevated"


def test_unknowns_widen_the_range_within_0_26():
    inp = FindriscInputs(**{**FULL, "waist_cm": None, "active_30min": None,
                            "daily_veg_fruit": None, "history_high_glucose": None})
    rng = score_range(inp)
    assert (rng.low, rng.high) == (6, 18)


def test_everything_unknown_still_bounded():
    rng = score_range(FindriscInputs(None, None, None, None, None, None, None, None, None))
    assert rng.low == 0 and rng.high == 26


def test_known_high_glucose_raises_low_and_narrows_range():
    base = FindriscInputs(**{**FULL, "waist_cm": None, "active_30min": None,
                             "daily_veg_fruit": None, "history_high_glucose": None})
    after = FindriscInputs(**{**FULL, "waist_cm": None, "active_30min": None,
                              "daily_veg_fruit": None, "history_high_glucose": True})
    r0, r1 = score_range(base), score_range(after)
    assert r1.low > r0.low
    assert (r1.high - r1.low) < (r0.high - r0.low)


def test_waist_points_depend_on_sex_and_missing_sex_makes_waist_unknown():
    male = score_range(FindriscInputs(**{**FULL, "waist_cm": 90.0}))
    female = score_range(FindriscInputs(**{**FULL, "sex": "female", "waist_cm": 90.0}))
    assert female.low - male.low == 4  # 90 cm: pria 0 poin, wanita >88 = 4 poin
    nosex = score_range(FindriscInputs(**{**FULL, "sex": None, "waist_cm": 90.0}))
    assert nosex.low < nosex.high


def test_category_edges():
    assert category(0) == "low"
    assert category(6) == "low"
    assert category(7) == "slightly_elevated"
    assert category(20) == "high"
    assert category(26) == "very_high"
    with pytest.raises(ValueError):
        category(27)


def test_p10_is_monotonic_non_decreasing():
    values = [p10(s) for s in range(0, 27)]
    assert values == sorted(values)


def test_p10_moves_with_every_score_point_inside_a_category():
    # What-if kecil (mis. +2 poin aktivitas) harus menggeser kurva walau kategorinya sama.
    assert p10(7) < p10(9) < p10(11)


def test_p10_hits_the_category_value_at_the_category_midpoint():
    assert p10(9) == pytest.approx(0.04)   # tengah 7-11
    assert p10(13) == pytest.approx(0.17)  # tengah 12-14


def test_p10_is_clamped_at_the_extremes():
    assert p10(0) == pytest.approx(0.01)
    assert p10(26) == pytest.approx(0.50)
