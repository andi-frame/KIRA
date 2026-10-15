from datetime import timedelta

from sqlalchemy import text

from app.timeutil import utcnow

CREDS = {"phone": "081200000001", "username": "raka_dev", "pin": "123456", "consent": True}


async def register(client):
    r = await client.post("/auth/register", json=CREDS)
    assert r.status_code == 200, r.text
    return r.json()


async def test_daftar_dan_masuk_memberi_token_akses_dan_token_penyegar(client):
    reg = await register(client)
    assert reg["refresh_token"] and len(reg["refresh_token"]) > 40 and reg["expires_in"] == 3600
    login = (await client.post("/auth/login", json={"identifier": "raka_dev", "pin": "123456"})).json()
    assert login["refresh_token"] and login["refresh_token"] != reg["refresh_token"]  # tiap perangkat punya sesi sendiri


async def test_token_penyegar_ditukar_dengan_sepasang_token_baru_dan_yang_lama_hangus(client):
    old = (await register(client))["refresh_token"]
    r = await client.post("/auth/refresh", json={"refresh_token": old})
    assert r.status_code == 200
    new = r.json()
    assert new["refresh_token"] != old
    me = await client.get("/profile", headers={"Authorization": f"Bearer {new['access_token']}"})
    assert me.status_code == 200 and me.json()["username"] == "raka_dev"
    assert (await client.post("/auth/refresh", json={"refresh_token": old})).status_code == 401  # tidak bisa dipakai ulang
    assert (await client.post("/auth/refresh", json={"refresh_token": new["refresh_token"]})).status_code == 200


async def test_token_penyegar_asal_atau_kedaluwarsa_ditolak(client, engine):
    token = (await register(client))["refresh_token"]
    assert (await client.post("/auth/refresh", json={"refresh_token": "x" * 48})).status_code == 401
    assert (await client.post("/auth/refresh", json={"refresh_token": "pendek"})).status_code == 422
    async with engine.begin() as conn:
        await conn.execute(text("update auth_sessions set expires_at = :t"), {"t": utcnow() - timedelta(minutes=1)})
    expired = await client.post("/auth/refresh", json={"refresh_token": token})
    assert expired.status_code == 401 and "masuk lagi" in expired.json()["detail"].lower()


async def test_keluar_mengakhiri_sesi_di_server_dan_selalu_berhasil(client):
    token = (await register(client))["refresh_token"]
    assert (await client.post("/auth/logout", json={"refresh_token": token})).json() == {"ok": True}
    assert (await client.post("/auth/refresh", json={"refresh_token": token})).status_code == 401
    assert (await client.post("/auth/logout", json={"refresh_token": "y" * 48})).status_code == 200


async def test_hanya_hash_token_penyegar_yang_disimpan(client, engine):
    token = (await register(client))["refresh_token"]
    async with engine.connect() as conn:
        stored = (await conn.execute(text("select token_hash from auth_sessions"))).scalar_one()
    assert stored != token and len(stored) == 64


async def test_sesi_satu_perangkat_tidak_memengaruhi_perangkat_lain(client):
    a = await register(client)
    b = (await client.post("/auth/login", json={"identifier": "raka_dev", "pin": "123456"})).json()
    await client.post("/auth/logout", json={"refresh_token": a["refresh_token"]})
    assert (await client.post("/auth/refresh", json={"refresh_token": b["refresh_token"]})).status_code == 200


async def test_pendaftaran_tanpa_persetujuan_ditolak(client):
    r = await client.post("/auth/register", json={**CREDS, "consent": False})
    assert r.status_code == 422 and "persetujuan" in r.json()["detail"].lower()
    no_field = {k: v for k, v in CREDS.items() if k != "consent"}
    assert (await client.post("/auth/register", json=no_field)).status_code == 422
    assert (await client.post("/auth/login", json={"identifier": "raka_dev", "pin": "123456"})).status_code == 401
