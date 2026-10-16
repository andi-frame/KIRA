import json

from sqlalchemy import text

from tests.api.test_summary import raka_headers


async def test_pendaftar_baru_tercatat_sudah_menyetujui(client, auth_headers):
    me = (await client.get("/profile", headers=auth_headers)).json()
    assert me["consented"] is True


async def test_akun_lama_belum_menyetujui_sampai_memberi_persetujuan(client, auth_headers, engine):
    async with engine.begin() as conn:
        await conn.execute(text("update users set consented_at = null, consent_version = null"))
    assert (await client.get("/profile", headers=auth_headers)).json()["consented"] is False
    r = await client.post("/account/consent", headers=auth_headers)
    assert r.status_code == 200 and r.json()["consented"] is True and r.json()["version"]
    assert (await client.get("/profile", headers=auth_headers)).json()["consented"] is True


async def test_persetujuan_versi_lama_diminta_ulang(client, auth_headers, engine):
    async with engine.begin() as conn:
        await conn.execute(text("update users set consent_version = '2020-01'"))
    assert (await client.get("/profile", headers=auth_headers)).json()["consented"] is False


async def test_unduh_data_memuat_semua_milik_pengguna_tanpa_pin(client, session_maker):
    h = await raka_headers(client, session_maker)
    r = await client.get("/account/export", headers=h)
    assert r.status_code == 200
    body = r.json()
    assert body["account"]["username"] == "raka" and "pin_hash" not in json.dumps(body)
    assert body["profile"]["sex"] == "male" and body["profile"]["height_cm"] == 170
    assert len(body["logs"]) > 10 and all("items" in lg for lg in body["logs"])
    assert any(lg["items"] for lg in body["logs"])
    assert {"clinical_results", "risk_snapshots", "messages", "family_links", "diagnoses"} <= set(body)


async def test_unduh_data_tidak_memuat_data_orang_lain(client, auth_headers, session_maker):
    await raka_headers(client, session_maker)
    body = (await client.get("/account/export", headers=auth_headers)).json()
    assert body["logs"] == [] and body["account"]["username"] == "pengguna_uji"
    assert (await client.get("/account/export")).status_code == 401


async def test_hapus_akun_butuh_pin_yang_benar(client, auth_headers):
    wrong = await client.post("/account/delete", json={"pin": "000000"}, headers=auth_headers)
    assert wrong.status_code == 403 and "pin" in wrong.json()["detail"].lower()
    assert (await client.get("/profile", headers=auth_headers)).status_code == 200  # masih ada


async def test_hapus_akun_menghapus_semua_data_dan_membebaskan_nomor_dan_nama(client, session_maker, engine):
    h = await raka_headers(client, session_maker)
    async with engine.connect() as conn:
        uid = (await conn.execute(text("select id from users where username = 'raka'"))).scalar_one()
    r = await client.post("/account/delete", json={"pin": "123456"}, headers=h)
    assert r.status_code == 200 and r.json() == {"deleted": True}
    async with engine.connect() as conn:
        for table in ("logs", "clinical_results", "messages", "health_profiles", "risk_snapshots", "auth_sessions"):
            n = (await conn.execute(text(f"select count(*) from {table} where user_id = :u"), {"u": uid})).scalar_one()
            assert n == 0, table
        assert (await conn.execute(text("select count(*) from users"))).scalar_one() == 0
    again = await client.post(
        "/auth/register", json={"phone": "081234567890", "username": "raka", "pin": "654321", "consent": True}
    )
    assert again.status_code == 200  # nomor dan nama pengguna bisa dipakai lagi


async def test_hapus_akun_juga_menghapus_undangan_keluarga_ke_nomornya(client, auth_headers):
    reg = {"phone": "081200000088", "username": "tamu_88", "pin": "123456", "consent": True}
    invited = await client.post("/auth/register", json=reg)
    ih = {"Authorization": f"Bearer {invited.json()['access_token']}"}
    await client.post("/family/invite", json={"phone": "081200000088"}, headers=auth_headers)
    assert (await client.post("/account/delete", json={"pin": "123456"}, headers=ih)).status_code == 200
    members = (await client.get("/family", headers=auth_headers)).json()["members"]
    assert members == []


async def test_percobaan_pin_salah_saat_hapus_akun_dibatasi(client, auth_headers):
    for _ in range(5):
        assert (await client.post("/account/delete", json={"pin": "000000"}, headers=auth_headers)).status_code == 403
    blocked = await client.post("/account/delete", json={"pin": "123456"}, headers=auth_headers)
    assert blocked.status_code == 429


async def test_unduh_data_memuat_preferensi_dan_penggantian_rencana(client, auth_headers):
    assert (await client.get("/account/export", headers=auth_headers)).json()["plan_preferences"] is None
    await client.put("/plan/preferences", json={"wake_time": "05:30"}, headers=auth_headers)
    await client.post("/plan/today/swap", json={"slot": "lunch"}, headers=auth_headers)
    body = (await client.get("/account/export", headers=auth_headers)).json()
    assert body["plan_preferences"]["wake_time"] == "05:30"
    assert [o["slot"] for o in body["plan_overrides"]] == ["lunch"]
