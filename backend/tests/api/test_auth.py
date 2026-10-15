from sqlalchemy import text

CREDS = {"phone": "081200000001", "username": "raka_dev", "pin": "123456"}
LOGIN = {"identifier": "raka_dev", "pin": "123456"}


async def test_register_then_login(client):
    r = await client.post("/auth/register", json=CREDS)
    assert r.status_code == 200 and r.json()["access_token"]
    r = await client.post("/auth/login", json={"phone": CREDS["phone"], "pin": CREDS["pin"]})
    assert r.status_code == 200 and r.json()["access_token"]


async def test_wrong_pin_rejected(client):
    await client.post("/auth/register", json=CREDS)
    r = await client.post("/auth/login", json={**CREDS, "pin": "000000"})
    assert r.status_code == 401


async def test_unknown_phone_rejected(client):
    r = await client.post("/auth/login", json=CREDS)
    assert r.status_code == 401


async def test_duplicate_phone_conflict(client):
    await client.post("/auth/register", json=CREDS)
    r = await client.post("/auth/register", json=CREDS)
    assert r.status_code == 409


async def test_malformed_credentials_rejected(client):
    assert (await client.post("/auth/register", json={"phone": "abc", "pin": "123456"})).status_code == 422
    assert (await client.post("/auth/register", json={"phone": "081200000002", "pin": "12"})).status_code == 422


async def test_pin_is_stored_hashed(client, engine):
    await client.post("/auth/register", json=CREDS)
    async with engine.connect() as conn:
        stored = (await conn.execute(text("select pin_hash from users"))).scalar_one()
    assert stored != CREDS["pin"] and stored.startswith("$argon2")


async def test_repeated_wrong_pins_lock_the_account_for_a_while(client):
    await client.post("/auth/register", json=CREDS)
    for _ in range(5):
        assert (await client.post("/auth/login", json={**CREDS, "pin": "000000"})).status_code == 401
    locked = await client.post("/auth/login", json=CREDS)  # PIN benar pun ditolak selama terkunci
    assert locked.status_code == 429
    assert "coba lagi" in locked.json()["detail"].lower()


async def test_successful_login_resets_the_failure_counter(client):
    await client.post("/auth/register", json=CREDS)
    for _ in range(4):
        await client.post("/auth/login", json={**CREDS, "pin": "000000"})
    assert (await client.post("/auth/login", json=CREDS)).status_code == 200
    for _ in range(4):
        assert (await client.post("/auth/login", json={**CREDS, "pin": "000000"})).status_code == 401


PHONE_LOGIN = {"identifier": CREDS["phone"], "pin": CREDS["pin"]}


async def test_registrasi_wajib_punya_nama_pengguna_dan_nomor(client):
    no_username = await client.post("/auth/register", json={"phone": "081200000001", "pin": "123456"})
    no_phone = await client.post("/auth/register", json={"username": "raka_dev", "pin": "123456"})
    assert no_username.status_code == 422 and no_phone.status_code == 422


async def test_masuk_dengan_nama_pengguna_atau_nomor_menghasilkan_akun_sama(client):
    await client.post("/auth/register", json=CREDS)
    by_name = await client.post("/auth/login", json=LOGIN)
    by_phone = await client.post("/auth/login", json=PHONE_LOGIN)
    legacy = await client.post("/auth/login", json={"phone": CREDS["phone"], "pin": CREDS["pin"]})
    assert by_name.status_code == by_phone.status_code == legacy.status_code == 200
    me = lambda r: client.get("/profile", headers={"Authorization": f"Bearer {r.json()['access_token']}"})  # noqa: E731
    assert (await me(by_name)).json()["username"] == (await me(by_phone)).json()["username"] == "raka_dev"


async def test_nama_pengguna_tidak_membedakan_huruf_besar_kecil(client):
    await client.post("/auth/register", json={**CREDS, "username": "Raka_Dev"})
    assert (await client.post("/auth/login", json={"identifier": "RAKA_dev", "pin": "123456"})).status_code == 200
    me = await client.get("/profile", headers={"Authorization": "Bearer " + (await client.post("/auth/login", json=LOGIN)).json()["access_token"]})
    assert me.json()["username"] == "raka_dev"  # disimpan huruf kecil


async def test_nama_pengguna_atau_pin_salah_ditolak_dengan_pesan_yang_sama(client):
    await client.post("/auth/register", json=CREDS)
    unknown = await client.post("/auth/login", json={"identifier": "tidak_ada", "pin": "123456"})
    wrong = await client.post("/auth/login", json={**LOGIN, "pin": "000000"})
    assert unknown.status_code == wrong.status_code == 401
    assert unknown.json()["detail"] == wrong.json()["detail"]


async def test_nama_pengguna_ganda_dan_nomor_ganda_punya_pesan_berbeda(client):
    await client.post("/auth/register", json=CREDS)
    same_name = await client.post("/auth/register", json={**CREDS, "phone": "081200000002", "username": "RAKA_DEV"})
    same_phone = await client.post("/auth/register", json={**CREDS, "username": "lain_lagi"})
    assert same_name.status_code == 409 and "nama pengguna" in same_name.json()["detail"].lower()
    assert same_phone.status_code == 409 and "nomor" in same_phone.json()["detail"].lower()


import pytest  # noqa: E402


@pytest.mark.parametrize(
    "username",
    ["ab", "a" * 21, "1raka", "081200000001", "raka dev", "raka-dev", "raka@dev", "_raka", "raka!", "rakä"],
)
async def test_nama_pengguna_tidak_valid_ditolak(client, username):
    r = await client.post("/auth/register", json={**CREDS, "username": username})
    assert r.status_code == 422


@pytest.mark.parametrize("username", ["abc", "raka.dev", "raka_dev99", "r" + "a" * 19])
async def test_nama_pengguna_valid_diterima(client, username):
    assert (await client.post("/auth/register", json={**CREDS, "username": username})).status_code == 200


async def test_kunci_percobaan_dibagi_antara_nama_pengguna_dan_nomor(client):
    await client.post("/auth/register", json=CREDS)
    for ident in (CREDS["username"], CREDS["phone"], CREDS["username"], CREDS["phone"], CREDS["username"]):
        assert (await client.post("/auth/login", json={"identifier": ident, "pin": "000000"})).status_code == 401
    # PIN benar lewat jalur mana pun tetap terkunci: tidak bisa menghindari batas dengan berganti identitas
    assert (await client.post("/auth/login", json=LOGIN)).status_code == 429
    assert (await client.post("/auth/login", json=PHONE_LOGIN)).status_code == 429


async def test_akun_lama_tanpa_nama_pengguna_bisa_membuatnya_nanti(client, auth_headers, engine):
    async with engine.begin() as conn:  # meniru akun yang dibuat sebelum ada nama pengguna
        await conn.execute(text("update users set username = null"))
    me = await client.get("/profile", headers=auth_headers)
    assert me.json()["username"] is None
    r = await client.put("/auth/username", json={"username": "Dian_01"}, headers=auth_headers)
    assert r.status_code == 200 and r.json() == {"username": "dian_01"}
    assert (await client.post("/auth/login", json={"identifier": "dian_01", "pin": "123456"})).status_code == 200
    assert (await client.get("/profile", headers=auth_headers)).json()["username"] == "dian_01"


async def test_ubah_nama_pengguna_ditolak_bila_dipakai_orang_lain_atau_tidak_valid(client, auth_headers):
    await client.post("/auth/register", json={"phone": "081200000050", "username": "dipakai", "pin": "123456"})
    assert (await client.put("/auth/username", json={"username": "DIPAKAI"}, headers=auth_headers)).status_code == 409
    assert (await client.put("/auth/username", json={"username": "1x"}, headers=auth_headers)).status_code == 422
    assert (await client.put("/auth/username", json={"username": "baru_ok"})).status_code == 401


async def test_mengganti_ke_nama_sendiri_tidak_dianggap_bentrok(client, auth_headers):
    await client.put("/auth/username", json={"username": "saya_ok"}, headers=auth_headers)
    assert (await client.put("/auth/username", json={"username": "Saya_Ok"}, headers=auth_headers)).status_code == 200


async def test_akun_demo_raka_bisa_masuk_dengan_nama_pengguna(client, session_maker):
    from seed.raka import RAKA_PIN, RAKA_USERNAME, create_raka

    async with session_maker() as session:
        await create_raka(session)
    assert (await client.post("/auth/login", json={"identifier": RAKA_USERNAME, "pin": RAKA_PIN})).status_code == 200
