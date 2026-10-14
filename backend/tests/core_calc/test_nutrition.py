import pytest

from app.core_calc.nutrition import FoodRecord, match_food, nutrition_for

FOODS = [
    FoodRecord("es_teh_manis", "Es teh manis", ["es teh", "teh manis dingin"],
               {"sugar_g": 8, "sodium_mg": 5, "fat_g": 0, "kcal": 32, "carb_g": 8}, 250),
    FoodRecord("rendang", "Rendang sapi", ["rendang"],
               {"sugar_g": 1, "sodium_mg": 600, "fat_g": 20, "kcal": 193, "carb_g": 4}, 70),
]


def test_sugar_scales_with_portion():
    result = nutrition_for(FOODS[0], 250)
    assert result["sugar_g"] == pytest.approx(20.0)
    assert result["portion_g"] == 250


def test_default_portion_used_when_grams_missing():
    assert nutrition_for(FOODS[1], None)["portion_g"] == 70


def test_match_by_alias_case_insensitive():
    assert match_food("Es Teh", FOODS).id == "es_teh_manis"


def test_match_tolerates_small_typo():
    assert match_food("rendag", FOODS).id == "rendang"


def test_unknown_food_returns_none():
    assert match_food("xyzxyz", FOODS) is None
    assert match_food("", FOODS) is None


def test_zero_or_negative_grams_rejected():
    with pytest.raises(ValueError):
        nutrition_for(FOODS[0], 0)


def _food(fid, name, aliases=()):
    return FoodRecord(fid, name, list(aliases), {"sugar_g": 0, "sodium_mg": 0, "fat_g": 0, "kcal": 0, "carb_g": 0}, 100)


def test_single_word_matches_the_only_food_containing_it():
    foods = [_food("rendang", "Rendang sapi"), _food("nasi", "Nasi putih")]
    assert match_food("rendang", foods).id == "rendang"


def test_ambiguous_word_returns_none_instead_of_guessing():
    foods = [_food("ayam_goreng", "Ayam goreng"), _food("ayam_bakar", "Ayam bakar")]
    assert match_food("ayam", foods) is None


def test_same_food_via_several_labels_is_not_ambiguous():
    foods = [_food("rendang", "Rendang sapi", ["rendang daging"])]
    assert match_food("rendang", foods).id == "rendang"
