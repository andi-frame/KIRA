import pytest

from app.core_calc.findrisc import FindriscInputs, score_range
from app.core_calc.whatif import WhatIfChange, simulate

BASE = dict(
    age=28, bmi=27.0, sex="male", waist_cm=95.0, active_30min=False, daily_veg_fruit=True,
    on_bp_medication=False, history_high_glucose=False, family_history="first_degree",
)


def run(change, inputs=None, height=170.0, weight=78.0, avg=2.0, sugar=20.0):
    return simulate(inputs or FindriscInputs(**BASE), height, weight, change, avg, sugar)


def test_no_change_means_before_equals_after():
    r = run(WhatIfChange())
    assert r.before == r.after
    assert r.most_impactful == "none"


def test_becoming_active_drops_two_points():
    r = run(WhatIfChange(active_30min=True))
    assert r.before.high - r.after.high == 2
    assert r.most_impactful == "activity"


def test_fewer_sweet_drinks_reduce_sugar_not_score():
    r = run(WhatIfChange(sweet_drinks_delta_per_day=-1))
    assert r.sugar_g_before == pytest.approx(40.0)
    assert r.sugar_g_after == pytest.approx(20.0)
    assert r.before == r.after
    assert r.most_impactful == "sweet_drinks"


def test_sugar_never_goes_negative():
    r = run(WhatIfChange(sweet_drinks_delta_per_day=-5))
    assert r.sugar_g_after == 0.0


def test_weight_loss_lowers_bmi_points():
    r = run(WhatIfChange(weight_delta_kg=-10))
    assert r.before.high - r.after.high == 1
    assert r.most_impactful == "weight"


def test_weight_change_ignored_when_height_or_weight_unknown():
    r = run(WhatIfChange(weight_delta_kg=-10), height=None)
    assert r.before == r.after


def test_most_impactful_picks_largest_score_drop():
    r = run(WhatIfChange(active_30min=True, weight_delta_kg=-10, sweet_drinks_delta_per_day=-1))
    assert r.most_impactful == "activity"
    assert r.after.high == score_range(FindriscInputs(**{**BASE, "active_30min": True, "bmi": 23.5})).high
