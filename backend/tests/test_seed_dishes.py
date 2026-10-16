"""Integritas seed hidangan dan komponen: id ada, angka bersumber, alias tidak bentrok, gram konsisten."""
import json

import pytest

from seed.load import SEED_DIR, _component_rows, _dish_rows, _food_rows

FOODS = {r["id"]: r for r in _food_rows()}
COMPONENTS = {r["id"]: r for r in _component_rows()}
DISHES = _dish_rows()
RAW_COMPONENTS = json.loads((SEED_DIR / "components.json").read_text(encoding="utf-8"))["rows"]


def labels(row):
    return [row["name"].lower(), *row["aliases"]]


def test_minimal_25_hidangan_dan_40_komponen():
    assert len(DISHES) >= 25 and len(COMPONENTS) >= 40


def test_id_komponen_tidak_bentrok_dengan_makanan():
    assert not set(COMPONENTS) & set(FOODS)


@pytest.mark.parametrize("dish", DISHES, ids=lambda d: d["id"])
def test_setiap_food_id_hidangan_ada_di_tabel(dish):
    missing = [c["food_id"] for c in dish["components"] if c["food_id"] not in FOODS | COMPONENTS]
    assert not missing


@pytest.mark.parametrize("dish", DISHES, ids=lambda d: d["id"])
def test_porsi_hidangan_sama_dengan_jumlah_gram_komponen(dish):
    assert dish["serving_g"] == pytest.approx(sum(c["grams"] for c in dish["components"]))
    assert 2 <= len(dish["components"]) <= 8
    assert "asumsi" in dish["source_note"].lower()


def test_setiap_komponen_punya_sumber_dan_catatan_asal_angka():
    for fid, *_, source, note in RAW_COMPONENTS:
        assert source.startswith(("TKPI:", "USDA:", "ESTIMASI")), fid
        assert note and "porsi: estimasi" in note, fid
        if source == "ESTIMASI":
            assert "Estimasi KIRA" in note, fid


def test_semua_nilai_gizi_komponen_terisi_dan_tidak_negatif():
    for row in COMPONENTS.values():
        assert set(row["per100g"]) == {"sugar_g", "sodium_mg", "fat_g", "kcal", "carb_g"}
        assert all(v is not None and v >= 0 for v in row["per100g"].values()), row["id"]


def test_nama_dan_alias_tidak_bentrok_antar_makanan_komponen_dan_hidangan():
    owner: dict[str, str] = {}
    for row in [*FOODS.values(), *COMPONENTS.values()]:
        for label in labels(row):
            assert owner.setdefault(label, row["id"]) == row["id"], f"{label!r}: {owner[label]} vs {row['id']}"
    for dish in DISHES:
        for label in labels(dish):
            assert label not in owner, f"alias hidangan {label!r} sudah dipakai makanan {owner.get(label)}"
