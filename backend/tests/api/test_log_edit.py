"""Ubah dan hapus catatan: saklar setengah porsi, hapus, koreksi lewat chat tanpa catatan dobel, waktu makan yang ditanyakan,
dan hitung ulang turunan (snapshot risiko) setelah perubahan."""
from datetime import datetime, timezone

import pytest
from sqlalchemy import func, select

from app.models import Log, RiskSnapshot
from app.timeutil import WIB, local_date, utcnow
from tests.api.helpers import complete_profile, install_models, reset_models

GEPREK = {"items": [{"name": "ayam geprek", "dish_id": "ayam_geprek", "meal_time": "lunch"}], "drinks": [],
          "activity": [], "clinical_result": None, "intent": "log"}
GEPREK_NO_TIME = {**GEPREK, "items": [{"name": "ayam geprek", "dish_id": "ayam_geprek"}]}


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    reset_models()


async def say(client, headers, text="catat"):
    r = await client.post("/chat/message", json={"text": text}, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


async def kcal_today(client, headers) -> float:
    r = await client.get("/logs/history", params={"days": 1}, headers=headers)
    return r.json()["days"][0]["totals"]["kcal"]


def kcal_of(log: dict) -> float:
    return sum(i["kcal"] or 0 for i in log["items"])


async def test_setengah_porsi_adalah_saklar_dan_tidak_menurun_berulang(client, auth_headers):
    install_models(extract=GEPREK)
    meal = (await say(client, auth_headers))["meals"][0]
    full, group = kcal_of(meal), meal["items"][0]["group"]

    for _ in range(3):  # ketuk berkali-kali: tetap setengah, bukan seperempat, seperdelapan, ...
        r = await client.patch(f"/logs/{meal['id']}", json={"half": True, "group": group}, headers=auth_headers)
        assert r.status_code == 200, r.text
        assert kcal_of(r.json()) == pytest.approx(full / 2, rel=0.01)
        assert r.json()["halved_groups"] == [group]

    r = await client.patch(f"/logs/{meal['id']}", json={"half": False, "group": group}, headers=auth_headers)
    assert kcal_of(r.json()) == pytest.approx(full, rel=0.01) and r.json()["halved_groups"] == []
    r = await client.patch(f"/logs/{meal['id']}", json={"half": False, "group": group}, headers=auth_headers)
    assert kcal_of(r.json()) == pytest.approx(full, rel=0.01)  # kembali ke biasa berulang juga tidak menggandakan
    assert await kcal_today(client, auth_headers) == pytest.approx(full, abs=0.2)


async def test_hapus_catatan_menurunkan_total_dan_hilang_dari_riwayat(client, auth_headers):
    install_models(extract=GEPREK)
    meal = (await say(client, auth_headers))["meals"][0]
    assert await kcal_today(client, auth_headers) > 0
    assert (await client.delete(f"/logs/{meal['id']}", headers=auth_headers)).status_code == 204
    assert await kcal_today(client, auth_headers) == 0
    day = (await client.get("/logs/history", params={"days": 1}, headers=auth_headers)).json()["days"][0]
    assert day["meals"] == [] and day["logged"] is False
    assert (await client.delete(f"/logs/{meal['id']}", headers=auth_headers)).status_code == 404


async def test_tidak_bisa_mengubah_atau_menghapus_catatan_orang_lain(client, auth_headers):
    install_models(extract=GEPREK)
    meal = (await say(client, auth_headers))["meals"][0]
    other = await client.post("/auth/register", json={"phone": "081200000002", "username": "orang_lain", "consent": True, "pin": "123456"})
    headers = {"Authorization": f"Bearer {other.json()['access_token']}"}
    assert (await client.patch(f"/logs/{meal['id']}", json={"half": True}, headers=headers)).status_code == 404
    assert (await client.delete(f"/logs/{meal['id']}", headers=headers)).status_code == 404


async def test_ubah_olahraga_dan_tidur_dari_riwayat(client, auth_headers):
    install_models(extract={"items": [], "drinks": [], "sleep": {"bed_time": "23:00", "wake_time": "05:00"},
                            "activity": [{"kind": "jalan kaki", "minutes": 20}], "clinical_result": None, "intent": "log"})
    body = await say(client, auth_headers)
    day = (await client.get("/logs/history", params={"days": 1}, headers=auth_headers)).json()["days"][0]
    [act], [slp] = day["activities"], day["sleeps"]
    assert act["minutes"] == 20 and slp["hours"] == 6

    r = await client.patch(f"/logs/{act['log_id']}", json={"minutes": 45, "activity_kind": "bersepeda"}, headers=auth_headers)
    assert r.status_code == 200 and r.json()["extracted"]["minutes"] == 45
    r = await client.patch(f"/logs/{slp['log_id']}", json={"bed_time": "22:00"}, headers=auth_headers)
    assert r.json()["extracted"]["hours"] == 7  # jam dihitung ulang dari jam tidur dan bangun yang baru

    day = (await client.get("/logs/history", params={"days": 1}, headers=auth_headers)).json()["days"][0]
    assert day["activity_minutes"] == 45 and day["sleep_hours"] == 7
    assert day["activities"][0]["kind"] == "bersepeda" and day["sleeps"][0]["bed_time"] == "22:00"
    assert (await client.delete(f"/logs/{act['log_id']}", headers=auth_headers)).status_code == 204
    day = (await client.get("/logs/history", params={"days": 1}, headers=auth_headers)).json()["days"][0]
    assert day["activity_minutes"] is None and day["activities"] == []


async def test_ubah_waktu_catatan_tidak_boleh_di_masa_depan(client, auth_headers):
    install_models(extract=GEPREK)
    meal = (await say(client, auth_headers))["meals"][0]
    future = (utcnow().replace(microsecond=0) + __import__("datetime").timedelta(hours=3)).isoformat()
    r = await client.patch(f"/logs/{meal['id']}", json={"occurred_at": future}, headers=auth_headers)
    assert r.status_code == 422


async def test_patch_kosong_ditolak(client, auth_headers):
    install_models(extract=GEPREK)
    meal = (await say(client, auth_headers))["meals"][0]
    assert (await client.patch(f"/logs/{meal['id']}", json={}, headers=auth_headers)).status_code == 422


# ---------- waktu makan ----------

def _clock(monkeypatch, hour: int, minute: int = 0):
    fixed = datetime.combine(local_date(utcnow()), datetime.min.time(), tzinfo=WIB).replace(hour=hour, minute=minute)
    monkeypatch.setattr("app.graph.nodes.save_logs.utcnow", lambda: fixed.astimezone(timezone.utc))


async def test_makan_berat_di_jam_selingan_ditanyakan_bukan_ditebak(client, auth_headers, monkeypatch):
    _clock(monkeypatch, 15, 30)
    chat, _ = install_models(extract=GEPREK_NO_TIME)
    out = await say(client, auth_headers, "aku sudah makan nasi dengan ayam katsu")
    meal = out["meals"][0]
    assert meal["slot_confirmed"] is False and meal["meal_slot"] == "snack"
    system_notes = "\n".join(str(m.content) for m in chat.seen[-1])
    assert "belum pasti" in system_notes and "sarapan, makan siang, makan malam, atau selingan" in system_notes

    r = await client.patch(f"/logs/{meal['id']}", json={"meal_slot": "lunch"}, headers=auth_headers)
    assert r.status_code == 200 and r.json()["meal_slot"] == "lunch" and r.json()["slot_confirmed"] is True
    plan = (await client.get("/plan/today", headers=auth_headers)).json()
    lunch = next(m for m in plan["meals"] if m["slot"] == "lunch")
    assert lunch["done"] is True  # rencana makan siang menandai ini sudah dimakan


async def test_waktu_makan_yang_disebut_pengguna_tidak_ditanya(client, auth_headers, monkeypatch):
    _clock(monkeypatch, 15, 30)
    install_models(extract=GEPREK)  # meal_time=lunch disebut pengguna
    meal = (await say(client, auth_headers, "tadi makan siang ayam geprek"))["meals"][0]
    assert meal["meal_slot"] == "lunch" and meal["slot_confirmed"] is True


async def test_makan_di_jam_inti_tidak_ditanya(client, auth_headers, monkeypatch):
    _clock(monkeypatch, 12, 15)
    install_models(extract=GEPREK_NO_TIME)
    meal = (await say(client, auth_headers))["meals"][0]
    assert meal["meal_slot"] == "lunch" and meal["slot_confirmed"] is True


# ---------- koreksi lewat chat ----------

async def count_logs(engine) -> int:
    from sqlalchemy.ext.asyncio import async_sessionmaker
    async with async_sessionmaker(engine)() as s:
        return (await s.execute(select(func.count()).select_from(Log))).scalar_one()


async def test_koreksi_setengah_porsi_lewat_chat_mengubah_catatan_bukan_membuat_baru(client, auth_headers, engine):
    install_models(extract=GEPREK)
    meal = (await say(client, auth_headers, "makan siang ayam geprek"))["meals"][0]
    full = kcal_of(meal)
    before = await count_logs(engine)

    install_models(extract={"items": [], "drinks": [], "activity": [], "clinical_result": None, "intent": "correction",
                            "correction": {"action": "update", "target": "meal", "match_text": "ayam geprek", "portion_scale": 0.5}})
    out = await say(client, auth_headers, "ralat, tadi cuma setengah porsi")
    assert await count_logs(engine) == before  # tidak dobel
    assert await kcal_today(client, auth_headers) == pytest.approx(full / 2, rel=0.02)
    assert out["meals"][0]["halved_groups"]  # tombol di aplikasi menjadi "Porsi biasa", bukan setengah lagi
    assert out["meals"][0]["id"] == meal["id"]


async def test_koreksi_waktu_makan_lewat_jawaban_singkat(client, auth_headers, monkeypatch):
    _clock(monkeypatch, 15, 30)
    install_models(extract=GEPREK_NO_TIME)
    meal = (await say(client, auth_headers, "makan nasi ayam katsu"))["meals"][0]
    assert meal["slot_confirmed"] is False
    install_models(extract={"items": [], "drinks": [], "activity": [], "clinical_result": None, "intent": "correction",
                            "correction": {"action": "update", "target": "meal", "meal_time": "lunch"}})
    out = await say(client, auth_headers, "makan siang")
    assert out["meals"][0]["meal_slot"] == "lunch" and out["meals"][0]["slot_confirmed"] is True


async def test_ganti_isi_makanan_lewat_chat(client, auth_headers, engine):
    install_models(extract=GEPREK)
    meal = (await say(client, auth_headers, "makan siang ayam geprek"))["meals"][0]
    install_models(extract={"items": [], "drinks": [], "activity": [], "clinical_result": None, "intent": "correction",
                            "correction": {"action": "update", "target": "meal", "match_text": "geprek",
                                           "replacement_items": [{"name": "nasi goreng", "food_id": "nasi_goreng"}]}})
    out = await say(client, auth_headers, "bukan ayam geprek, tapi nasi goreng")
    assert out["meals"][0]["id"] == meal["id"]
    assert {i["name"].lower() for i in out["meals"][0]["items"]} != {i["name"].lower() for i in meal["items"]}
    assert await count_logs(engine) == 1


async def test_hapus_lewat_chat_dan_tidak_ditemukan_tidak_mencatat_baru(client, auth_headers, engine):
    install_models(extract=GEPREK)
    await say(client, auth_headers, "makan siang ayam geprek")
    install_models(extract={"items": [], "drinks": [], "activity": [], "clinical_result": None, "intent": "correction",
                            "correction": {"action": "delete", "target": "meal"}})
    await say(client, auth_headers, "hapus catatan makan yang tadi")
    assert await count_logs(engine) == 0
    chat, _ = install_models(extract={"items": [], "drinks": [], "activity": [], "clinical_result": None, "intent": "correction",
                                      "correction": {"action": "delete", "target": "activity", "match_text": "renang"}})
    await say(client, auth_headers, "hapus renang tadi")
    assert await count_logs(engine) == 0
    assert "Tidak ada catatan" in "\n".join(str(m.content) for m in chat.seen[-1])


async def test_koreksi_olahraga_lewat_chat(client, auth_headers):
    install_models(extract={"items": [], "drinks": [], "sleep": None, "activity": [{"kind": "jalan kaki", "minutes": 20}],
                            "clinical_result": None, "intent": "log"})
    await say(client, auth_headers, "jalan kaki 20 menit")
    install_models(extract={"items": [], "drinks": [], "activity": [], "clinical_result": None, "intent": "correction",
                            "correction": {"action": "update", "target": "activity", "minutes": 40}})
    await say(client, auth_headers, "ralat, jalannya 40 menit")
    day = (await client.get("/logs/history", params={"days": 1}, headers=auth_headers)).json()["days"][0]
    assert day["activity_minutes"] == 40 and len(day["activities"]) == 1


# ---------- hitung ulang turunan ----------

async def test_snapshot_risiko_mengikuti_perubahan_dan_tidak_menggembung(client, auth_headers, engine):
    from sqlalchemy.ext.asyncio import async_sessionmaker
    await complete_profile(client, auth_headers, usual_active_30min=False)
    install_models(extract={"items": [], "drinks": [], "activity": [{"kind": "jalan kaki", "minutes": 90}],
                            "clinical_result": None, "intent": "log"})
    act_id = (await say(client, auth_headers, "jalan 90 menit"))["log_ids"][0]

    async def snapshots() -> int:
        async with async_sessionmaker(engine)() as s:
            return (await s.execute(select(func.count()).select_from(RiskSnapshot))).scalar_one()

    n = await snapshots()
    for minutes in (60, 60, 60):  # perubahan yang tidak menggeser skor tidak menambah baris
        r = await client.patch(f"/logs/{act_id}", json={"minutes": minutes}, headers=auth_headers)
        assert r.status_code == 200
    assert await snapshots() <= n + 1
