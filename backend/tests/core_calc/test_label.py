import pytest

from app.core_calc.label import LabelFacts, label_totals


def _facts(**kw) -> LabelFacts:
    base = dict(basis="per_serving", serving_g=250, servings_consumed=1, sugar_g=24, sodium_mg=50, fat_g=0, kcal=100)
    return LabelFacts(**{**base, **kw})


def test_per_sajian_dikali_jumlah_sajian_yang_dimakan():
    t = label_totals(_facts(servings_consumed=2))
    assert t == {"portion_g": 500, "sugar_g": 48, "sodium_mg": 100, "fat_g": 0, "kcal": 200}


def test_per_100g_diskalakan_dengan_takaran_saji():
    t = label_totals(_facts(basis="per_100g", serving_g=30, sugar_g=10, sodium_mg=500, fat_g=20, kcal=500))
    assert t["portion_g"] == 30
    assert t["sugar_g"] == pytest.approx(3)
    assert t["sodium_mg"] == pytest.approx(150)
    assert t["fat_g"] == pytest.approx(6)
    assert t["kcal"] == pytest.approx(150)


def test_per_100g_tanpa_takaran_saji_tidak_bisa_dihitung():
    assert label_totals(_facts(basis="per_100g", serving_g=None)) is None


def test_zat_yang_tidak_tertera_tetap_kosong_bukan_nol():
    t = label_totals(_facts(sugar_g=None))
    assert t["sugar_g"] is None
    assert t["sodium_mg"] == 50


def test_per_sajian_tanpa_takaran_tetap_menghitung_zat_tanpa_porsi_gram():
    t = label_totals(_facts(serving_g=None))
    assert t["portion_g"] is None
    assert t["sugar_g"] == 24


@pytest.mark.parametrize(
    "kw",
    [
        dict(sugar_g=300),  # gula melebihi berat satu sajian
        dict(fat_g=-1),
        dict(basis="per_100g", serving_g=30, sugar_g=101),
        dict(basis="per_100g", serving_g=30, kcal=950),
        dict(basis="per_100g", serving_g=30, sodium_mg=50000),
        dict(servings_consumed=0),
    ],
)
def test_nilai_mustahil_ditolak(kw):
    with pytest.raises(ValueError):
        label_totals(_facts(**kw))
