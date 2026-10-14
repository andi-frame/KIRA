from app.core_calc import constants as c


def test_categories_cover_0_to_26_without_gaps_or_overlap():
    covered = []
    for lo, hi, _label in c.FINDRISC_CATEGORIES:
        covered.extend(range(lo, hi + 1))
    assert sorted(covered) == list(range(0, 27))


def test_p10_is_monotonic_in_category_order_and_a_probability():
    labels = [label for _, _, label in c.FINDRISC_CATEGORIES]
    values = [c.P10_BY_CATEGORY[label] for label in labels]
    assert values == sorted(values)
    assert all(0 < v < 1 for v in values)


def test_every_category_label_has_a_p10():
    assert {label for _, _, label in c.FINDRISC_CATEGORIES} == set(c.P10_BY_CATEGORY)


def test_findrisc_max_points_is_26():
    p = c.FINDRISC_POINTS
    top = (
        p["age"]["top"]
        + p["bmi"]["top"]
        + max(p["waist"]["male"]["top"], p["waist"]["female"]["top"])
        + p["activity_no"]
        + p["veg_fruit_no"]
        + p["bp_medication_yes"]
        + p["high_glucose_yes"]
        + max(p["family_history"].values())
    )
    assert top == 26


def test_red_flag_thresholds_are_present_and_sane():
    sys_, dia = c.RED_FLAG_BP
    assert sys_ > c.BP_THRESHOLDS["hypertension"][0]
    assert dia > c.BP_THRESHOLDS["hypertension"][1]
    assert c.RED_FLAG_GLUCOSE["low"] < c.RED_FLAG_GLUCOSE["high"]
    assert "nyeri dada" in c.RED_FLAG_KEYWORDS


def test_management_is_stricter_than_prevention():
    assert 0 < c.MANAGEMENT_STRICTNESS < 1
