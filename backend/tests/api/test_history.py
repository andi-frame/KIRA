"""GET /logs/history: riwayat makan per hari dengan gizi, batas harian sesuai mode, dan halaman lebih lama."""
from datetime import date, timedelta

import pytest

from app.timeutil import local_date, utcnow
from tests.api.helpers import install_models, reset_models

LUNCH = {"items": [{"name": "ayam geprek", "dish_id": "ayam_geprek"}],
         "drinks": [{"name": "es teh manis", "size": "gelas", "count": 2}],
         "sleep": {"hours": 6}, "activity": [{"kind": "jalan kaki", "minutes": 30}], "clinical_result": None,
         "intent": "log"}


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    reset_models()


def today() -> date:
    return local_date(utcnow())


async def history(client, headers, **params):
    r = await client.get("/logs/history", params=params, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


async def test_pengguna_baru_mendapat_hari_tidak_tercatat_bukan_nol(client, auth_headers):
    body = await history(client, auth_headers)
    assert len(body["days"]) == 14
    assert body["days"][0]["date"] == today().isoformat()  # terbaru dulu
    assert body["days"][-1]["date"] == (today() - timedelta(days=13)).isoformat()
    assert all(d["logged"] is False and d["meals"] == [] for d in body["days"])
    assert body["days"][0]["limits"] == {"sugar_g": 50.0, "sodium_mg": 2000.0, "fat_g": 67.0}
    assert body["days"][0]["sleep_hours"] is None and body["days"][0]["activity_minutes"] is None


async def test_hari_ini_memuat_makan_minum_tidur_aktivitas_dan_total(client, auth_headers):
    install_models(extract=LUNCH)
    await client.post("/chat/message", json={"text": "siang ayam geprek, 2 es teh, tidur 6 jam, jalan 30 menit"},
                      headers=auth_headers)
    day = (await history(client, auth_headers, days=1))["days"][0]
    assert day["logged"] is True and day["sleep_hours"] == 6 and day["activity_minutes"] == 30
    [meal], [drink] = day["meals"], day["drinks"]
    assert meal["title"] == "Ayam geprek" and len(meal["items"]) == 4 and meal["uncounted"] == 0
    assert {i["group"] for i in meal["items"]} == {"Ayam geprek"} and meal["source"] == "text"
    assert drink["title"] == "2x es teh manis"
    for key in ("kcal", "sugar_g", "sodium_mg", "fat_g"):
        assert day["totals"][key] == pytest.approx(meal["totals"][key] + drink["totals"][key], abs=0.11)
    assert meal["totals"]["kcal"] == pytest.approx(sum(i["kcal"] for i in meal["items"]), abs=0.11)


async def test_halaman_lebih_lama_lewat_next_before(client, auth_headers):
    first = await history(client, auth_headers, days=7)
    assert first["next_before"] == (today() - timedelta(days=6)).isoformat()
    older = await history(client, auth_headers, days=7, before=first["next_before"])
    assert older["days"][0]["date"] == (today() - timedelta(days=7)).isoformat()
    assert older["days"][-1]["date"] == (today() - timedelta(days=13)).isoformat()


async def test_tanggal_masa_depan_tidak_melewati_hari_ini(client, auth_headers):
    body = await history(client, auth_headers, days=3, before=(today() + timedelta(days=30)).isoformat())
    assert body["days"][0]["date"] == today().isoformat()


async def test_mode_pengelolaan_memakai_batas_gula_lebih_ketat(client, auth_headers):
    await client.post("/diagnoses", json={"condition": "prediabetes"}, headers=auth_headers)
    day = (await history(client, auth_headers, days=1))["days"][0]
    assert day["limits"]["sugar_g"] == 25.0


async def test_data_pengguna_lain_tidak_bocor_dan_butuh_login(client, auth_headers):
    install_models(extract=LUNCH)
    await client.post("/chat/message", json={"text": "makan ayam geprek"}, headers=auth_headers)
    other = await client.post("/auth/register", json={"phone": "081200000031", "username": "orang_lain",
                                                      "pin": "123456", "consent": True})
    oh = {"Authorization": f"Bearer {other.json()['access_token']}"}
    assert all(not d["logged"] for d in (await history(client, oh))["days"])
    assert (await client.get("/logs/history")).status_code == 401
    assert (await client.get("/logs/history", params={"days": 61}, headers=auth_headers)).status_code == 422
