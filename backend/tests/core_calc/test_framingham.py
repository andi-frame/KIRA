import pytest

from app.core_calc.framingham import (
    FraminghamInputs,
    category,
    eligibility,
    risk_4y,
    risk_range,
)


def man(**kw):
    base = dict(age=45, female=False, sbp=120, dbp=80, smoker=False, parental=0, bmi=25.0)
    return FraminghamInputs(**{**base, **kw})


def test_reference_values_from_the_published_weibull_model():
    # Dihitung dengan koefisien Parikh 2008 (halaman FHS risk functions): intercept 22,94954, skala 0,87692.
    assert risk_4y(man()) == pytest.approx(0.08597, abs=1e-4)
    assert risk_4y(man(female=True)) == pytest.approx(0.10712, abs=1e-4)
    assert risk_4y(man(age=60, sbp=135, dbp=88, smoker=True, parental=1, bmi=31.0)) == pytest.approx(0.62784, abs=1e-4)
    assert risk_4y(man(age=30, sbp=110, dbp=70, bmi=22.0)) == pytest.approx(0.01029, abs=1e-4)


@pytest.mark.parametrize(
    "worse",
    [dict(sbp=130), dict(dbp=85), dict(bmi=30.0), dict(smoker=True), dict(parental=1), dict(female=True), dict(age=55)],
)
def test_each_risk_factor_raises_the_risk(worse):
    assert risk_4y(man(**worse)) > risk_4y(man())


def test_risk_is_a_probability():
    for kw in (dict(), dict(sbp=139, dbp=89, age=69, smoker=True, parental=2, bmi=40.0), dict(sbp=90, dbp=55, age=20)):
        assert 0 < risk_4y(man(**kw)) < 1


def test_categories_follow_the_paper_cutoffs():
    assert category(0.049) == "low"
    assert category(0.05) == "medium"
    assert category(0.10) == "medium"
    assert category(0.101) == "high"


def test_unknown_smoking_and_parental_history_give_a_range():
    lo, hi = risk_range(age=45, female=False, sbp=120, dbp=80, bmi=25.0, smoker=None, parental_options=(0, 1, 2))
    assert lo == pytest.approx(risk_4y(man()))
    assert hi == pytest.approx(risk_4y(man(smoker=True, parental=2)))
    assert lo < hi


def test_known_inputs_collapse_the_range_to_a_point():
    lo, hi = risk_range(age=45, female=False, sbp=120, dbp=80, bmi=25.0, smoker=False, parental_options=(0,))
    assert lo == hi


@pytest.mark.parametrize(
    "kwargs,expected",
    [
        (dict(age=45, sbp=120, dbp=80, has_diabetes=False), None),
        (dict(age=19, sbp=120, dbp=80, has_diabetes=False), "out_of_age_range"),
        (dict(age=70, sbp=120, dbp=80, has_diabetes=False), "out_of_age_range"),
        (dict(age=45, sbp=145, dbp=80, has_diabetes=False), "already_hypertensive"),
        (dict(age=45, sbp=120, dbp=92, has_diabetes=False), "already_hypertensive"),
        (dict(age=45, sbp=120, dbp=80, has_diabetes=True), "has_diabetes"),
    ],
)
def test_the_model_is_only_applied_where_it_was_derived(kwargs, expected):
    # Kohort asal: usia 20-69, tanpa diabetes, belum hipertensi.
    assert eligibility(**kwargs) == expected
