from app.core_calc.constants import DAILY_LIMITS
from app.core_calc.targets import Totals, remaining_targets


def test_remaining_is_limit_minus_consumed():
    r = remaining_targets(Totals(20, 500, 10), "prevention")
    assert r.sugar_g == DAILY_LIMITS["sugar_g"] - 20
    assert r.sodium_mg == DAILY_LIMITS["sodium_mg"] - 500
    assert r.fat_g == DAILY_LIMITS["fat_g"] - 10


def test_never_negative():
    assert remaining_targets(Totals(60, 0, 0), "prevention").sugar_g == 0


def test_management_leaves_less_sugar_and_never_more_of_anything():
    consumed = Totals(20, 500, 10)
    p = remaining_targets(consumed, "prevention")
    m = remaining_targets(consumed, "management")
    assert m.sugar_g < p.sugar_g
    assert m.sodium_mg <= p.sodium_mg and m.fat_g <= p.fat_g
