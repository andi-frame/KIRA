"""GET /dashboard: Beranda dalam satu panggilan, dari catatan pengguna sendiri."""
from datetime import datetime, timedelta, timezone

import pytest

from app.services.dashboard import build_dashboard
from tests.api.helpers import PROFILE_RAKA, install_models, reset_models

LUNCH = {"items": [{"name": "ayam geprek", "dish_id": "ayam_geprek"}], "drinks": [], "sleep": {"hours": 5},
         "activity": [{"kind": "jalan kaki", "minutes": 20}], "clinical_result": None, "intent": "log"}


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    reset_models()


async def dash(client, headers):
    r = await client.get("/dashboard", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


async def test_pengguna_baru_data_kurang_dan_ajakan_mencatat(client, auth_headers):
    body = await dash(client, auth_headers)
    assert body["data_quality"] == "kurang" and body["logged_days"] == 0
    assert body["today"]["nutrition"]["kcal"] == 0 and body["today"]["meals_logged"] == 0
    assert body["today"]["nutrition"]["limits"]["sugar_g"] == 50.0
    assert body["today"]["sleep_hours_last_night"] is None
    plan = body["plan_today"]
    assert [m["slot"] for m in plan["meals"]] == ["breakfast", "lunch", "snack", "dinner"]
    assert body["today"]["nutrition"]["kcal_target"] == 2150  # bawaan sampai profil diisi
    assert body["today"]["sleep_target"]["bedtime"] == plan["sleep"]["bedtime"] == "22:00"
    assert [s["key"] for s in body["signals"]] == ["result_no_results", "data"]  # info, tanpa menyimpulkan kebiasaan
    assert len(body["week"]["days"]) == 7 and body["next_best_action"]["kind"] in {"log_meal", "exercise", "sleep"}


async def test_catatan_baru_langsung_mengubah_kondisi_hari_ini(client, auth_headers):
    install_models(extract=LUNCH)
    await client.post("/chat/message", json={"text": "siang ayam geprek, tidur 5 jam, jalan 20 menit"}, headers=auth_headers)
    today = (await dash(client, auth_headers))["today"]
    assert today["meals_logged"] == 1 and today["nutrition"]["kcal"] > 400
    assert today["sleep_hours_last_night"] == 5 and today["activity_minutes"] == 20
    history_day = (await client.get("/logs/history", params={"days": 1}, headers=auth_headers)).json()["days"][0]
    assert today["nutrition"]["kcal"] == pytest.approx(history_day["totals"]["kcal"])  # angka sama di Beranda dan Riwayat


async def test_proyeksi_sama_dengan_layar_proyeksi(client, auth_headers):
    await client.put("/profile", json=PROFILE_RAKA, headers=auth_headers)
    body = await dash(client, auth_headers)
    projection = (await client.get("/projection", headers=auth_headers)).json()
    assert body["risk"] == projection
    assert "points" in body["risk_history"]


async def test_hasil_cek_perhatian_menjadi_langkah_pertama(client, auth_headers):
    await client.post("/results", json={"kind": "blood_pressure", "value": {"sys": 150, "dia": 95}}, headers=auth_headers)
    body = await dash(client, auth_headers)
    assert body["signals"][0]["key"] == "result_blood_pressure" and body["signals"][0]["level"] == "perhatian"
    assert body["next_best_action"]["kind"] == "check"


async def test_data_pengguna_lain_tidak_bocor_dan_butuh_login(client, auth_headers):
    install_models(extract=LUNCH)
    await client.post("/chat/message", json={"text": "ayam geprek"}, headers=auth_headers)
    other = await client.post("/auth/register", json={"phone": "081200000041", "username": "tetangga_tiga",
                                                      "pin": "123456", "consent": True})
    oh = {"Authorization": f"Bearer {other.json()['access_token']}"}
    assert (await dash(client, oh))["today"]["meals_logged"] == 0
    assert (await client.get("/dashboard")).status_code == 401


async def test_langkah_berikutnya_mengikuti_jam(session_maker, make_user):
    uid = await make_user()
    wib = timezone(timedelta(hours=7))
    async with session_maker() as session:
        morning = await build_dashboard(session, uid, now=datetime(2026, 10, 16, 8, tzinfo=wib))
        afternoon = await build_dashboard(session, uid, now=datetime(2026, 10, 16, 15, tzinfo=wib))
    assert morning["next_best_action"]["kind"] == "exercise"  # belum waktunya sarapan dianggap terlewat
    assert afternoon["next_best_action"] == {
        "kind": "log_meal", "text": "Belum ada catatan sarapan. Ceritakan di Ngobrol, satu kalimat cukup."}
