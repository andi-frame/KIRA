import re
from datetime import timedelta

import pytest
from sqlalchemy import text

from app.config import settings
from app.timeutil import utcnow

SECRET = {"X-Bot-Secret": "s3cret"}
JID = "6281200000001@s.whatsapp.net"
LOGIN = {"identifier": "pengguna_uji", "pin": "123456"}


@pytest.fixture(autouse=True)
def _bot(monkeypatch):
    monkeypatch.setattr(settings, "bot_secret", "s3cret")


async def link_whatsapp(client, headers):
    code = (await client.post("/whatsapp/link-code", headers=headers)).json()["code"]
    r = await client.post("/webhooks/whatsapp", headers=SECRET, json={"jid": JID, "text": code})
    assert r.status_code == 200


async def outbox_code(client):
    """Kode yang diterima pengguna: diambil dari antrean pesan keluar, persis seperti yang dikirim bot."""
    msgs = (await client.get("/webhooks/whatsapp/outbox", headers=SECRET)).json()["messages"]
    otp = [m for m in msgs if m["kind"] == "otp"]
    assert otp, msgs
    return re.search(r"\b(\d{6})\b", otp[-1]["text"]).group(1), otp[-1]


async def test_kode_dikirim_ke_whatsapp_tertaut_lalu_pin_baru_berlaku(client, auth_headers):
    await link_whatsapp(client, auth_headers)
    r = await client.post("/auth/pin-reset/request", json={"identifier": "pengguna_uji"})
    assert r.status_code == 200 and "whatsapp" in r.json()["message"].lower()
    code, msg = await outbox_code(client)
    assert msg["jid"] == JID and "jangan bagikan" in msg["text"].lower()

    done = await client.post(
        "/auth/pin-reset/confirm", json={"identifier": "pengguna_uji", "code": code, "new_pin": "654321"}
    )
    assert done.status_code == 200 and done.json() == {"ok": True}
    assert (await client.post("/auth/login", json=LOGIN)).status_code == 401  # PIN lama tidak berlaku
    assert (await client.post("/auth/login", json={**LOGIN, "pin": "654321"})).status_code == 200


async def test_kode_hanya_bisa_dipakai_sekali(client, auth_headers):
    await link_whatsapp(client, auth_headers)
    await client.post("/auth/pin-reset/request", json={"identifier": "pengguna_uji"})
    code, _ = await outbox_code(client)
    body = {"identifier": "pengguna_uji", "code": code, "new_pin": "654321"}
    assert (await client.post("/auth/pin-reset/confirm", json=body)).status_code == 200
    again = await client.post("/auth/pin-reset/confirm", json={**body, "new_pin": "111111"})
    assert again.status_code == 400
    assert (await client.post("/auth/login", json={**LOGIN, "pin": "111111"})).status_code == 401


async def test_jawaban_permintaan_sama_untuk_akun_ada_tanpa_whatsapp_dan_tidak_ada(client, auth_headers):
    known_no_wa = await client.post("/auth/pin-reset/request", json={"identifier": "pengguna_uji"})
    unknown = await client.post("/auth/pin-reset/request", json={"identifier": "tidak_ada_orang"})
    assert known_no_wa.status_code == unknown.status_code == 200
    assert known_no_wa.json() == unknown.json()
    msgs = (await client.get("/webhooks/whatsapp/outbox", headers=SECRET)).json()["messages"]
    assert [m for m in msgs if m["kind"] == "otp"] == []  # tidak ada yang dikirim


async def test_kode_salah_ditolak_dan_dikunci_setelah_lima_kali(client, auth_headers):
    await link_whatsapp(client, auth_headers)
    await client.post("/auth/pin-reset/request", json={"identifier": "pengguna_uji"})
    code, _ = await outbox_code(client)
    wrong = "000000" if code != "000000" else "111111"
    body = {"identifier": "pengguna_uji", "code": wrong, "new_pin": "654321"}
    for _ in range(4):
        assert (await client.post("/auth/pin-reset/confirm", json=body)).status_code == 400
    assert (await client.post("/auth/pin-reset/confirm", json=body)).status_code == 429
    right = await client.post("/auth/pin-reset/confirm", json={**body, "code": code})
    assert right.status_code == 429  # kode benar pun tidak diterima setelah terkunci
    assert (await client.post("/auth/login", json=LOGIN)).status_code == 200  # PIN lama tidak berubah


async def test_kode_kedaluwarsa_ditolak(client, auth_headers, engine):
    await link_whatsapp(client, auth_headers)
    await client.post("/auth/pin-reset/request", json={"identifier": "pengguna_uji"})
    code, _ = await outbox_code(client)
    async with engine.begin() as conn:
        await conn.execute(text("update pin_reset_codes set expires_at = :t"), {"t": utcnow() - timedelta(seconds=1)})
    body = {"identifier": "pengguna_uji", "code": code, "new_pin": "654321"}
    r = await client.post("/auth/pin-reset/confirm", json=body)
    assert r.status_code == 400 and "kedaluwarsa" in r.json()["detail"].lower()


async def test_hanya_hash_kode_yang_disimpan_dan_teks_dihapus_setelah_terkirim(client, auth_headers, engine):
    await link_whatsapp(client, auth_headers)
    await client.post("/auth/pin-reset/request", json={"identifier": "pengguna_uji"})
    code, msg = await outbox_code(client)
    async with engine.connect() as conn:
        stored = (await conn.execute(text("select code_hash from pin_reset_codes"))).scalar_one()
    assert code not in stored and len(stored) == 64
    await client.post(f"/webhooks/whatsapp/outbox/{msg['id']}/ack", headers=SECRET)
    async with engine.connect() as conn:
        kept = (await conn.execute(text("select text from wa_outbox where id = :i"), {"i": msg["id"]})).scalar_one()
    assert code not in kept


async def test_permintaan_beruntun_tidak_membanjiri_whatsapp(client, auth_headers):
    await link_whatsapp(client, auth_headers)
    for _ in range(2):
        assert (await client.post("/auth/pin-reset/request", json={"identifier": "pengguna_uji"})).status_code == 200
    msgs = (await client.get("/webhooks/whatsapp/outbox", headers=SECRET)).json()["messages"]
    assert len([m for m in msgs if m["kind"] == "otp"]) == 1  # permintaan kedua dalam 60 detik tidak mengirim ulang
    for _ in range(2):
        await client.post("/auth/pin-reset/request", json={"identifier": "pengguna_uji"})
    limited = await client.post("/auth/pin-reset/request", json={"identifier": "pengguna_uji"})
    assert limited.status_code == 429


async def test_atur_ulang_mengeluarkan_semua_perangkat_dan_membuka_kunci_masuk(client, auth_headers):
    session = (await client.post("/auth/login", json=LOGIN)).json()
    await link_whatsapp(client, auth_headers)
    for _ in range(5):
        await client.post("/auth/login", json={**LOGIN, "pin": "000000"})
    assert (await client.post("/auth/login", json=LOGIN)).status_code == 429  # terkunci
    await client.post("/auth/pin-reset/request", json={"identifier": "pengguna_uji"})
    code, _ = await outbox_code(client)
    await client.post("/auth/pin-reset/confirm", json={"identifier": "pengguna_uji", "code": code, "new_pin": "654321"})
    assert (await client.post("/auth/refresh", json={"refresh_token": session["refresh_token"]})).status_code == 401
    assert (await client.post("/auth/login", json={**LOGIN, "pin": "654321"})).status_code == 200


async def test_masukan_tidak_valid_ditolak(client):
    bad_code = {"identifier": "x", "code": "12ab56", "new_pin": "654321"}
    assert (await client.post("/auth/pin-reset/confirm", json=bad_code)).status_code == 422
    bad_pin = {"identifier": "x", "code": "123456", "new_pin": "12"}
    assert (await client.post("/auth/pin-reset/confirm", json=bad_pin)).status_code == 422
    unknown = {"identifier": "tidak_ada", "code": "123456", "new_pin": "654321"}
    assert (await client.post("/auth/pin-reset/confirm", json=unknown)).status_code == 400


async def test_ganti_pin_saat_masuk_butuh_pin_lama_dan_mengeluarkan_perangkat_lain(client, auth_headers):
    other = (await client.post("/auth/login", json=LOGIN)).json()
    wrong = await client.put("/auth/pin", json={"current_pin": "000000", "new_pin": "654321"}, headers=auth_headers)
    assert wrong.status_code == 403
    ok = await client.put("/auth/pin", json={"current_pin": "123456", "new_pin": "654321"}, headers=auth_headers)
    assert ok.status_code == 200 and ok.json()["refresh_token"]
    assert (await client.post("/auth/login", json={**LOGIN, "pin": "654321"})).status_code == 200
    assert (await client.post("/auth/login", json=LOGIN)).status_code == 401
    assert (await client.post("/auth/refresh", json={"refresh_token": other["refresh_token"]})).status_code == 401
    assert (await client.post("/auth/refresh", json={"refresh_token": ok.json()["refresh_token"]})).status_code == 200
