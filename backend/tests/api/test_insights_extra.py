from datetime import datetime, timedelta, timezone

from sqlalchemy import text

from app.repos import logs as logs_repo
from app.timeutil import WIB
from tests.api.helpers import complete_profile
from tests.api.test_summary import raka_headers


async def user_id(session_maker):
    async with session_maker() as s:
        return (await s.execute(text("select id from users limit 1"))).scalar_one()


def when(days_ago: int, hour: int = 12) -> datetime:
    local = datetime.now(WIB).replace(hour=hour, minute=0, second=0, microsecond=0) - timedelta(days=days_ago)
    return local.astimezone(timezone.utc)


async def log(session_maker, uid, kind, days_ago, extracted, sugar=None, hour=12):
    async with session_maker() as s:
        items = [logs_repo.ItemData(name="x", sugar_g=sugar)] if sugar is not None else []
        await logs_repo.add_log(s, uid, kind=kind, source="text", occurred_at=when(days_ago, hour),
                                extracted=extracted, raw_text=None, items=items)


async def test_pola_tidur_pendek_membandingkan_gula_hari_yang_sama(client, auth_headers, session_maker):
    uid = await user_id(session_maker)
    for d in (1, 2, 3):  # tidur 5 jam, gula tinggi
        await log(session_maker, uid, "sleep", d, {"hours": 5.0}, hour=7)
        await log(session_maker, uid, "meal", d, {"items": []}, sugar=70)
    for d in (4, 5, 6):  # tidur 8 jam, gula rendah
        await log(session_maker, uid, "sleep", d, {"hours": 8.0}, hour=7)
        await log(session_maker, uid, "meal", d, {"items": []}, sugar=30)
    body = (await client.get("/insights/patterns?days=30", headers=auth_headers)).json()
    sleep = body["sleep"]
    assert sleep["threshold_hours"] == 6.0 and sleep["short_days"] == 3 and sleep["other_days"] == 3
    sugar = next(c for c in sleep["comparisons"] if c["key"] == "sugar_g")
    assert (sugar["short_avg"], sugar["other_avg"], sugar["diff"]) == (70, 30, 40)
    assert "bukan sebab pasti" in body["disclaimer"]


async def test_pola_tensi_per_hari_dan_rata_rata_protokol_tidak_ikut(client, auth_headers, session_maker):
    uid = await user_id(session_maker)
    for d in (1, 2, 3):
        await log(session_maker, uid, "sleep", d, {"hours": 5.0}, hour=7)
    for d in (4, 5, 6):
        await log(session_maker, uid, "sleep", d, {"hours": 8.0}, hour=7)
    for d, sys in ((1, 140), (2, 138), (3, 142), (4, 120), (5, 122), (6, 118)):
        r = await client.post("/results", json={"kind": "blood_pressure", "value": {"sys": sys, "dia": 80}, "source": "self",
                                                 "measured_at": when(d).isoformat()}, headers=auth_headers)
        assert r.status_code == 200
    # rata-rata dari protokol rumah (tanggal acak) tidak mewakili satu hari: harus diabaikan
    await client.post("/results", json={"kind": "blood_pressure", "value": {"sys": 160, "dia": 95, "protocol": "x", "readings": 12},
                                        "source": "self", "measured_at": when(1).isoformat()}, headers=auth_headers)
    sleep = (await client.get("/insights/patterns?days=30", headers=auth_headers)).json()["sleep"]
    bp = next(c for c in sleep["comparisons"] if c["key"] == "systolic")
    assert (bp["short_avg"], bp["other_avg"]) == (140, 120)


async def test_pola_butuh_data_cukup_bukan_angka_palsu(client, auth_headers):
    body = (await client.get("/insights/patterns", headers=auth_headers)).json()
    assert body["sleep"]["needs_more_data"] is True and body["sleep"]["comparisons"] == []


async def test_pola_demo_raka_dan_batas_periode(client, session_maker):
    h = await raka_headers(client, session_maker)
    body = (await client.get("/insights/patterns?days=30", headers=h)).json()
    assert body["sleep"]["short_days"] >= 3  # Raka tidur 5 jam hampir tiap malam: kelompok pendek besar
    assert (await client.get("/insights/patterns?days=7", headers=h)).status_code == 422
    assert (await client.get("/insights/patterns?days=91", headers=h)).status_code == 422
    assert (await client.get("/insights/patterns")).status_code == 401


async def test_riwayat_risiko_satu_titik_per_hari_dan_batas_kategori(client, auth_headers, session_maker):
    await complete_profile(client, auth_headers)
    await client.post("/results", json={"kind": "fasting_glucose", "value": {"mg_dl": 95}, "source": "lab"}, headers=auth_headers)
    await client.post("/results", json={"kind": "blood_pressure", "value": {"sys": 120, "dia": 80}, "source": "self"}, headers=auth_headers)
    body = (await client.get("/insights/risk-history", headers=auth_headers)).json()
    assert len(body["points"]) == 1  # beberapa snapshot hari ini → satu titik (yang terakhir)
    p = body["points"][0]
    assert p["score_low"] <= p["score_high"] and p["category_low"] and p["category_high"]
    assert [c["category"] for c in body["categories"]] == ["low", "slightly_elevated", "moderate", "high", "very_high"]
    assert body["categories"][1] == {"min": 7, "max": 11, "category": "slightly_elevated"}


async def test_riwayat_risiko_menyempit_setelah_hasil_cek_masuk(client, auth_headers, engine):
    await complete_profile(client, auth_headers)
    await client.post("/results", json={"kind": "fasting_glucose", "value": {"mg_dl": 95}, "source": "lab"}, headers=auth_headers)
    async with engine.begin() as conn:  # geser snapshot-snapshot ke hari yang berbeda
        await conn.execute(text("update risk_snapshots set computed_at = computed_at - interval '3 days'"))
    await client.post("/results", json={"kind": "blood_pressure", "value": {"sys": 118, "dia": 76}, "source": "self"}, headers=auth_headers)
    points = (await client.get("/insights/risk-history", headers=auth_headers)).json()["points"]
    assert len(points) == 2 and points[0]["date"] < points[1]["date"]


async def test_riwayat_risiko_pengguna_baru_kosong_dan_batas(client, auth_headers):
    assert (await client.get("/insights/risk-history", headers=auth_headers)).json()["points"] == []
    assert (await client.get("/insights/risk-history?days=3", headers=auth_headers)).status_code == 422
    assert (await client.get("/insights/risk-history")).status_code == 401


# --- skenario "bagaimana kalau" tersimpan ---

SCENARIO = {"name": "  Jalan   kaki  dan kurangi teh manis ", "active_30min": True, "sweet_drinks_delta_per_day": -1}


async def test_simpan_skenario_menyimpan_hasil_saat_itu_dan_menghitung_ulang_sekarang(client, auth_headers):
    await complete_profile(client, auth_headers)
    r = await client.post("/projection/scenarios", json=SCENARIO, headers=auth_headers)
    assert r.status_code == 200, r.text
    s = r.json()
    assert s["name"] == "Jalan kaki dan kurangi teh manis"  # spasi dirapikan
    assert s["params"]["active_30min"] is True and s["params"]["sweet_drinks_delta_per_day"] == -1
    assert s["saved"]["after"]["high"] <= s["saved"]["before"]["high"]
    assert s["now"]["after"] == s["saved"]["after"] and s["now"]["before"] == s["saved"]["before"]
    listed = (await client.get("/projection/scenarios", headers=auth_headers)).json()
    assert [x["id"] for x in listed["scenarios"]] == [s["id"]] and listed["max"] == 10


async def test_skenario_dihitung_ulang_saat_data_berubah_sedangkan_hasil_tersimpan_tetap(client, auth_headers):
    await complete_profile(client, auth_headers)
    saved = (await client.post("/projection/scenarios", json=SCENARIO, headers=auth_headers)).json()
    await client.post("/results", json={"kind": "fasting_glucose", "value": {"mg_dl": 96}, "source": "lab"}, headers=auth_headers)
    again = (await client.get("/projection/scenarios", headers=auth_headers)).json()["scenarios"][0]
    assert again["saved"] == saved["saved"]  # catatan saat disimpan tidak berubah
    assert again["now"]["before"] != saved["saved"]["before"]  # rentang sekarang menyempit


async def test_skenario_kosong_dan_nama_tidak_valid_ditolak(client, auth_headers):
    await complete_profile(client, auth_headers)
    assert (await client.post("/projection/scenarios", json={"name": "kosong"}, headers=auth_headers)).status_code == 422
    assert (await client.post("/projection/scenarios", json={"name": "nol", "weight_delta_kg": 0, "sweet_drinks_delta_per_day": 0}, headers=auth_headers)).status_code == 422
    assert (await client.post("/projection/scenarios", json={"name": "   ", "active_30min": True}, headers=auth_headers)).status_code == 422
    assert (await client.post("/projection/scenarios", json={"name": "x" * 41, "active_30min": True}, headers=auth_headers)).status_code == 422


async def test_batas_sepuluh_skenario_dan_hapus_membukanya_lagi(client, auth_headers):
    await complete_profile(client, auth_headers)
    ids = []
    for i in range(10):
        r = await client.post("/projection/scenarios", json={"name": f"s{i}", "active_30min": True}, headers=auth_headers)
        ids.append(r.json()["id"])
    over = await client.post("/projection/scenarios", json={"name": "lebih", "active_30min": True}, headers=auth_headers)
    assert over.status_code == 409 and "Hapus satu dulu" in over.json()["detail"]
    assert (await client.delete(f"/projection/scenarios/{ids[0]}", headers=auth_headers)).status_code == 200
    assert (await client.post("/projection/scenarios", json={"name": "lagi", "active_30min": True}, headers=auth_headers)).status_code == 200


async def test_skenario_milik_sendiri_dan_butuh_login(client, auth_headers):
    await complete_profile(client, auth_headers)
    sid = (await client.post("/projection/scenarios", json=SCENARIO, headers=auth_headers)).json()["id"]
    other = await client.post("/auth/register", json={"phone": "081200000031", "username": "orang_dua", "pin": "123456", "consent": True})
    oh = {"Authorization": f"Bearer {other.json()['access_token']}"}
    assert (await client.get("/projection/scenarios", headers=oh)).json()["scenarios"] == []
    assert (await client.delete(f"/projection/scenarios/{sid}", headers=oh)).status_code == 404
    assert (await client.get("/projection/scenarios")).status_code == 401
    assert (await client.post("/projection/scenarios", json=SCENARIO)).status_code == 401
