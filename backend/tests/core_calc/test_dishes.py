import pytest

from app.core_calc.dishes import DishComponent, DishRecord, expand_dish, match_dish, match_dish_exact, scale_for
from app.core_calc.nutrition import nutrition_for
from tests.core_calc.seed_data import seed_dishes, seed_foods


def dishes():
    return list(seed_dishes())


@pytest.mark.parametrize("query,expected", [
    ("ayam geprek", "ayam_geprek"), ("Ayam Geprek level 5", "ayam_geprek"), ("geprek", "ayam_geprek"),
    ("ayam penyet", "ayam_penyet"), ("nasi ayam krispi", "nasi_ayam_krispi"), ("pecel lele", "pecel_lele"),
    ("nasi padang rendang", "nasi_padang"), ("mie ayam bakso", "mie_ayam_bakso"), ("indomie telur", "mie_instan_telur"),
])
def test_hidangan_umum_dikenali(query, expected):
    assert match_dish(query, dishes()).id == expected


@pytest.mark.parametrize("query", ["nasi goreng", "bakso", "nasi uduk", "rendang", "ayam goreng", "es teh manis"])
def test_makanan_tunggal_tidak_dibajak_hidangan(query):
    # kueri yang lebih pendek dari label hidangan tetap milik tabel foods ("nasi goreng" bukan "nasi goreng telur")
    assert match_dish(query, dishes()) is None


@pytest.mark.parametrize("query", ["ayam", "nasi", "", "makanan misterius"])
def test_ambigu_atau_tidak_dikenal_abstain(query):
    assert match_dish(query, dishes()) is None


def test_dua_hidangan_seri_dianggap_ambigu():
    a = DishRecord("a", "Paket satu", ("paket hemat",), 100, (DishComponent("nasi_putih", 100),))
    b = DishRecord("b", "Paket dua", ("hemat paket",), 100, (DishComponent("nasi_putih", 100),))
    assert match_dish("paket hemat banget", [a, b]) is None


def test_ayam_geprek_dipecah_menjadi_komponen_bergizi_dari_tabel():
    dish = match_dish("ayam geprek", dishes())
    parts = expand_dish(dish, seed_foods())
    assert [p.food.id for p in parts] == ["ayam_goreng_tepung", "nasi_putih", "sambal_bawang", "timun"]
    assert sum(p.grams for p in parts) == pytest.approx(dish.serving_g)
    # total = jumlah komponen, dihitung ulang langsung dari tabel
    expected_kcal = sum(seed_foods()[c.food_id].per100g["kcal"] * c.grams / 100 for c in dish.components)
    assert sum(nutrition_for(p.food, p.grams)["kcal"] for p in parts) == pytest.approx(expected_kcal)


def test_skala_porsi_gram_dan_jumlah_porsi():
    dish = match_dish("ayam geprek", dishes())
    half = expand_dish(dish, seed_foods(), servings=0.5)
    by_grams = expand_dish(dish, seed_foods(), portion_g=dish.serving_g / 2)
    assert [p.grams for p in half] == pytest.approx([c.grams / 2 for c in dish.components])
    assert [p.grams for p in by_grams] == pytest.approx([p.grams for p in half])
    assert scale_for(dish) == 1.0


@pytest.mark.parametrize("kw", [{"portion_g": 0}, {"servings": -1}])
def test_porsi_tidak_masuk_akal_ditolak(kw):
    with pytest.raises(ValueError):
        scale_for(dishes()[0], **kw)


def test_label_resep_dipakai_bila_ada():
    padang = match_dish("nasi padang", dishes())
    labels = [p.label for p in expand_dish(padang, seed_foods())]
    assert "kuah gulai" in labels and "Nasi putih" in labels


def test_komponen_tanpa_makanan_di_tabel_dilewati():
    dish = DishRecord("x", "X", (), 150, (DishComponent("nasi_putih", 100), DishComponent("tidak_ada", 50)))
    assert [p.food.id for p in expand_dish(dish, seed_foods())] == ["nasi_putih"]


@pytest.mark.parametrize("query", [
    "nasi ayam katsu scrambled egg",  # "nasi ayam" ada di alias nasi ayam goreng, tetapi katsu dan scrambled egg bukan bagian resep itu
    "nasi ayam katsu", "nasi ayam bakar madu", "nasi ayam goreng keju",
])
def test_kata_makanan_lain_di_kueri_tidak_dipaksa_menjadi_hidangan_yang_hanya_mirip(query):
    assert match_dish(query, dishes()) is None


@pytest.mark.parametrize("query,expected", [
    ("ayam geprek level 5", "ayam_geprek"), ("2 porsi ayam geprek", "ayam_geprek"), ("nasi ayam goreng", "nasi_ayam_goreng"),
    ("pecel lele level 3", "pecel_lele"), ("ayam penyet pedas banyak", "ayam_penyet"),
])
def test_kata_pelengkap_dan_angka_tidak_mengubah_hidangan(query, expected):
    assert match_dish(query, dishes()).id == expected


def test_pencocokan_persis_hanya_nama_atau_alias():
    assert match_dish_exact("nasi ayam", dishes()).id == "nasi_ayam_goreng"
    assert match_dish_exact("Ayam Geprek", dishes()).id == "ayam_geprek"
    assert match_dish_exact("ayam geprek level 5", dishes()) is None
    assert match_dish_exact("", dishes()) is None
