"""/plan: preferensi, rencana hari ini (adaptif), rencana minggu, dan ganti usulan."""
import pytest

from tests.api.helpers import PROFILE_RAKA, install_models, reset_models

LUNCH = {"items": [{"name": "ayam geprek", "dish_id": "ayam_geprek"}], "drinks": [], "sleep": None,
         "activity": [{"kind": "jalan cepat", "minutes": 45}], "clinical_result": None, "intent": "log"}


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    reset_models()


async def get(client, headers, path):
    r = await client.get(path, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


async def test_preferensi_bawaan_lalu_disimpan(client, auth_headers):
    prefs = await get(client, auth_headers, "/plan/preferences")
    assert prefs["wake_time"] == "06:00" and prefs["channels"] == {"app": True, "whatsapp": False}
    r = await client.put("/plan/preferences", json={"wake_time": "05:30", "exercise_days": [5, 1, 1, 3], "goal": "turun_berat",
                                                    "meal_times": {"lunch": "12:30"}, "quiet_hours": {"start": "22:00", "end": "05:00"}},
                         headers=auth_headers)
    assert r.status_code == 200, r.text
    saved = r.json()
    assert saved["wake_time"] == "05:30" and saved["exercise_days"] == [1, 3, 5] and saved["goal"] == "turun_berat"
    assert saved["meal_times"]["lunch"] == "12:30" and saved["meal_times"]["breakfast"] == "06:30"
    assert saved["quiet_hours"] == {"start": "22:00", "end": "05:00"}
    assert (await get(client, auth_headers, "/plan/preferences")) == saved


@pytest.mark.parametrize("body", [{"wake_time": "25:00"}, {"exercise_days": [7]}, {"goal": "bulking"},
                                  {"meal_times": {"brunch": "10:00"}}, {"strength_days": 5}])
async def test_preferensi_tidak_masuk_akal_ditolak(client, auth_headers, body):
    assert (await client.put("/plan/preferences", json=body, headers=auth_headers)).status_code == 422


async def test_rencana_hari_ini_memakai_akg_dan_jam_bangun(client, auth_headers):
    await client.put("/profile", json=PROFILE_RAKA, headers=auth_headers)
    await client.put("/plan/preferences", json={"wake_time": "05:00"}, headers=auth_headers)
    plan = await get(client, auth_headers, "/plan/today")
    assert plan["energy"]["kcal"] == 2650 and "Permenkes 28/2019" in plan["energy"]["source"]
    assert [m["slot"] for m in plan["meals"]] == ["breakfast", "lunch", "snack", "dinner"]
    assert all(m["title"] and m["components"] for m in plan["meals"])
    assert plan["sleep"]["bedtime"] == "21:00" and plan["sleep"]["hours"] == 8  # belum ada catatan tidur
    assert "bukan resep" in plan["disclaimer"] and plan["adapted"] is None


async def test_rencana_hari_ini_menyesuaikan_catatan(client, auth_headers):
    install_models(extract=LUNCH)
    await client.post("/chat/message", json={"text": "ayam geprek, jalan cepat 45 menit"}, headers=auth_headers)
    plan = await get(client, auth_headers, "/plan/today")
    assert plan["consumed"]["kcal"] > 400 and plan["adapted"].startswith("Disesuaikan")
    assert sum(m["done"] for m in plan["meals"]) == 1
    if plan["exercise"]:
        assert plan["exercise"]["done_minutes"] == 45


async def test_rencana_minggu_tujuh_hari_dan_stabil(client, auth_headers):
    week = await get(client, auth_headers, "/plan/week")
    assert len(week["days"]) == 7 and week["days"][0]["date"] == week["start"]
    assert week == await get(client, auth_headers, "/plan/week")


async def test_ganti_usulan_mengubah_satu_bagian_saja(client, auth_headers):
    before = await get(client, auth_headers, "/plan/today")
    r = await client.post("/plan/today/swap", json={"slot": "lunch"}, headers=auth_headers)
    assert r.status_code == 200
    after = r.json()
    by = lambda p: {m["slot"]: m["id"] for m in p["meals"]}  # noqa: E731
    assert by(after)["lunch"] != by(before)["lunch"]
    assert by(after)["breakfast"] == by(before)["breakfast"]
    assert by(await get(client, auth_headers, "/plan/today")) == by(after)  # tersimpan
    assert (await client.post("/plan/today/swap", json={"slot": "brunch"}, headers=auth_headers)).status_code == 422


async def test_tensi_perhatian_tidak_memberi_latihan_baru(client, auth_headers):
    await client.post("/results", json={"kind": "blood_pressure", "value": {"sys": 165, "dia": 100}}, headers=auth_headers)
    week = await get(client, auth_headers, "/plan/week")
    exercises = [d["exercise"] for d in week["days"] if d["exercise"]]
    assert exercises and all(e["blocked"] and e["minutes"] == 0 for e in exercises)


async def test_preferensi_tidak_suka_dari_profil(client, auth_headers):
    await client.put("/profile", json={**PROFILE_RAKA, "food_preferences": {"dislikes": ["telur", "lele"]}}, headers=auth_headers)
    week = await get(client, auth_headers, "/plan/week")
    names = " ".join(c["name"].lower() for d in week["days"] for m in d["meals"] for c in m.get("components", []))
    assert "telur" not in names and "lele" not in names


async def test_rencana_milik_sendiri_dan_butuh_login(client, auth_headers):
    for path in ("/plan/today", "/plan/week", "/plan/preferences"):
        assert (await client.get(path)).status_code == 401
    await client.put("/plan/preferences", json={"wake_time": "04:30"}, headers=auth_headers)
    other = await client.post("/auth/register", json={"phone": "081200000051", "username": "tetangga_empat",
                                                      "pin": "123456", "consent": True})
    oh = {"Authorization": f"Bearer {other.json()['access_token']}"}
    assert (await get(client, oh, "/plan/preferences"))["wake_time"] == "06:00"


async def test_waktu_makan_dari_ekstraksi_menang_atas_jam_catatan(client, auth_headers):
    # "tadi siang ..." dikirim pagi hari: yang ditandai sudah adalah makan siang, bukan sarapan
    install_models(extract={**LUNCH, "items": [{"name": "ayam geprek", "dish_id": "ayam_geprek", "meal_time": "lunch"}]})
    await client.post("/chat/message", json={"text": "tadi siang ayam geprek"}, headers=auth_headers)
    done = {m["slot"] for m in (await get(client, auth_headers, "/plan/today"))["meals"] if m["done"]}
    assert done == {"lunch"}
