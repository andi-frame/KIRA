"""GET /foods/search dan koreksi catatan hidangan per komponen (PATCH /logs/{id}: skala, hapus komponen)."""
import pytest

from tests.api.helpers import install_models, reset_models

GEPREK = {"items": [{"name": "ayam geprek", "dish_id": "ayam_geprek"}], "drinks": [], "sleep": None, "activity": [],
          "clinical_result": None, "intent": "log"}


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    reset_models()


async def search(client, headers, q, **params):
    return await client.get("/foods/search", params={"q": q, **params}, headers=headers)


async def test_hidangan_dan_makanan_disarankan(client, auth_headers):
    r = await search(client, auth_headers, "ayam geprek")
    assert r.status_code == 200
    first = r.json()["results"][0]
    assert first == {"kind": "dish", "id": "ayam_geprek", "name": "Ayam geprek", "score": 1.0, "portion_g": 305}
    assert any(x["kind"] == "food" for x in r.json()["results"])


async def test_salah_ketik_tetap_mendapat_saran(client, auth_headers):
    results = (await search(client, auth_headers, "timunn")).json()["results"]
    assert results[0]["id"] == "timun"


async def test_maksimal_delapan_tanpa_duplikat(client, auth_headers):
    results = (await search(client, auth_headers, "nasi")).json()["results"]
    assert 0 < len(results) <= 8 and len({(x["kind"], x["id"]) for x in results}) == len(results)
    assert (await search(client, auth_headers, "nasi", limit=9)).status_code == 422


async def test_pencarian_butuh_login_dan_kueri(client, auth_headers):
    assert (await client.get("/foods/search", params={"q": "nasi"})).status_code == 401
    assert (await search(client, auth_headers, "")).status_code == 422


async def logged_geprek(client, headers):
    install_models(extract=GEPREK)
    log_id = (await client.post("/chat/message", json={"text": "makan ayam geprek"}, headers=headers)).json()["log_ids"][0]
    items = (await client.get("/logs", headers=headers)).json()["logs"][0]["items"]
    return log_id, items


async def test_catatan_hidangan_menampilkan_komponen_terkelompok(client, auth_headers):
    _, items = await logged_geprek(client, auth_headers)
    assert len(items) == 4 and {i["group"] for i in items} == {"Ayam geprek"} and all(i["food_id"] for i in items)


async def test_setengah_porsi_seluruh_hidangan(client, auth_headers):
    log_id, items = await logged_geprek(client, auth_headers)
    r = await client.patch(f"/logs/{log_id}", json={"scale": 0.5, "group": "Ayam geprek"}, headers=auth_headers)
    assert r.status_code == 200 and r.json()["corrected"] is True
    after = {i["name"]: i for i in r.json()["items"]}
    for before in items:
        assert after[before["name"]]["portion_g"] == pytest.approx(before["portion_g"] / 2)
        assert after[before["name"]]["kcal"] == pytest.approx(before["kcal"] / 2)
        assert after[before["name"]]["group"] == "Ayam geprek"


async def test_hapus_satu_komponen_dan_ubah_porsi_komponen(client, auth_headers):
    log_id, items = await logged_geprek(client, auth_headers)
    keep = [{"name": i["name"], "portion_g": 200 if i["food_id"] == "ayam_goreng_tepung" else i["portion_g"],
             "food_id": i["food_id"], "group": i["group"]} for i in items if i["food_id"] != "nasi_putih"]  # "tanpa nasi"
    r = await client.patch(f"/logs/{log_id}", json={"items": keep}, headers=auth_headers)
    after = {i["food_id"]: i for i in r.json()["items"]}
    assert "nasi_putih" not in after and len(after) == 3
    chicken_before = next(i for i in items if i["food_id"] == "ayam_goreng_tepung")
    assert after["ayam_goreng_tepung"]["kcal"] == pytest.approx(chicken_before["kcal"] * 2)


async def test_patch_tanpa_isi_ditolak(client, auth_headers):
    log_id, _ = await logged_geprek(client, auth_headers)
    assert (await client.patch(f"/logs/{log_id}", json={}, headers=auth_headers)).status_code == 422
