"""Riwayat obrolan: tersimpan di server, satu per hari, dan dibersihkan saat hari berganti."""
from datetime import timedelta

import pytest
from sqlalchemy import update
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.models import Message
from tests.api.helpers import install_models, reset_models

LUNCH = {"items": [{"name": "ayam geprek", "dish_id": "ayam_geprek", "meal_time": "lunch"}], "drinks": [],
         "activity": [], "clinical_result": None, "intent": "log"}


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    reset_models()


async def history(client, headers):
    r = await client.get("/chat/history", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


async def test_obrolan_hari_ini_pulih_beserta_kartu_makan(client, auth_headers):
    assert (await history(client, auth_headers))["messages"] == []
    install_models(extract=LUNCH)
    sent = await client.post("/chat/message", json={"text": "makan siang ayam geprek"}, headers=auth_headers)
    body = await history(client, auth_headers)
    assert [m["role"] for m in body["messages"]] == ["user", "assistant"]
    assert body["messages"][0]["text"] == "makan siang ayam geprek"
    assistant = body["messages"][1]
    assert assistant["text"] == sent.json()["reply"]
    assert [m["id"] for m in assistant["meals"]] == sent.json()["log_ids"]  # kartu "Yang kucatat" bisa digambar ulang
    assert assistant["meals"][0]["items"], "isi kartu harus ikut"


async def test_kartu_di_riwayat_obrolan_memuat_isi_terkini_setelah_koreksi(client, auth_headers):
    install_models(extract=LUNCH)
    meal = (await client.post("/chat/message", json={"text": "makan siang"}, headers=auth_headers)).json()["meals"][0]
    await client.patch(f"/logs/{meal['id']}", json={"half": True, "group": meal["items"][0]["group"]}, headers=auth_headers)
    shown = (await history(client, auth_headers))["messages"][1]["meals"][0]
    assert sum(i["kcal"] or 0 for i in shown["items"]) == pytest.approx(sum(i["kcal"] or 0 for i in meal["items"]) / 2, rel=0.02)


async def test_catatan_yang_dihapus_hilang_dari_kartu_tetapi_pesan_tetap(client, auth_headers):
    install_models(extract=LUNCH)
    meal = (await client.post("/chat/message", json={"text": "makan siang"}, headers=auth_headers)).json()["meals"][0]
    await client.delete(f"/logs/{meal['id']}", headers=auth_headers)
    assistant = (await history(client, auth_headers))["messages"][1]
    assert assistant["meals"] == [] and assistant["text"]


async def test_obrolan_kemarin_dibersihkan_saat_hari_berganti(client, auth_headers, engine):
    install_models(extract=LUNCH)
    await client.post("/chat/message", json={"text": "kemarin makan"}, headers=auth_headers)
    async with async_sessionmaker(engine)() as s:
        await s.execute(update(Message).values(created_at=Message.created_at - timedelta(days=1)))
        await s.commit()
    assert (await history(client, auth_headers))["messages"] == []  # hari baru mulai bersih
    await client.post("/chat/message", json={"text": "hari ini makan"}, headers=auth_headers)
    assert [m["text"] for m in (await history(client, auth_headers))["messages"]][0] == "hari ini makan"


async def test_hapus_obrolan_hari_ini_tidak_menghapus_catatan(client, auth_headers):
    install_models(extract=LUNCH)
    await client.post("/chat/message", json={"text": "makan siang"}, headers=auth_headers)
    assert (await client.delete("/chat/history", headers=auth_headers)).status_code == 204
    assert (await history(client, auth_headers))["messages"] == []
    day = (await client.get("/logs/history", params={"days": 1}, headers=auth_headers)).json()["days"][0]
    assert len(day["meals"]) == 1


async def test_obrolan_milik_sendiri_saja(client, auth_headers):
    install_models(extract=LUNCH)
    await client.post("/chat/message", json={"text": "rahasia saya"}, headers=auth_headers)
    other = await client.post("/auth/register", json={"phone": "081200000002", "username": "orang_lain", "consent": True, "pin": "123456"})
    headers = {"Authorization": f"Bearer {other.json()['access_token']}"}
    assert (await history(client, headers))["messages"] == []


async def test_tugas_malam_membersihkan_semua_pengguna(client, auth_headers, session_maker):
    from app.services import jobs
    install_models(extract=LUNCH)
    await client.post("/chat/message", json={"text": "kemarin"}, headers=auth_headers)
    async with session_maker() as s:
        await s.execute(update(Message).values(created_at=Message.created_at - timedelta(days=2)))
        await s.commit()
    async with session_maker() as s:
        assert await jobs.purge_old_chats(s) == 2
