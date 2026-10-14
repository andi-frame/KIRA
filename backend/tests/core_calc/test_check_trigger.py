from app.core_calc.check_trigger import CheckRecommendation, evaluate_check
from app.core_calc.findrisc import ScoreRange


def test_range_crossing_categories_with_unknown_glucose_suggests_glucose():
    rec = evaluate_check(ScoreRange(6, 18), glucose_known=False, bp_known=True, habits_worsening=False)
    assert isinstance(rec, CheckRecommendation)
    assert rec.test_kind == "fasting_glucose"


def test_calm_and_fully_known_gives_nothing():
    assert evaluate_check(ScoreRange(3, 4), glucose_known=True, bp_known=True, habits_worsening=False) is None


def test_high_range_with_everything_measured_does_not_force_a_check():
    assert evaluate_check(ScoreRange(16, 18), glucose_known=True, bp_known=True, habits_worsening=False) is None


def test_trigger_with_glucose_known_but_bp_unknown_suggests_bp():
    rec = evaluate_check(ScoreRange(6, 18), glucose_known=True, bp_known=False, habits_worsening=False)
    assert rec.test_kind == "blood_pressure"


def test_unmeasured_bp_alone_suggests_bp_check():
    rec = evaluate_check(ScoreRange(3, 4), glucose_known=True, bp_known=False, habits_worsening=False)
    assert rec.test_kind == "blood_pressure"
    assert "tensi" in rec.reason.lower()


def test_worsening_habits_trigger_glucose_check():
    rec = evaluate_check(ScoreRange(3, 4), glucose_known=False, bp_known=True, habits_worsening=True)
    assert rec.test_kind == "fasting_glucose"


def test_reason_has_no_risk_numbers():
    rec = evaluate_check(ScoreRange(6, 18), glucose_known=False, bp_known=True, habits_worsening=False)
    assert not any(ch.isdigit() for ch in rec.reason)
