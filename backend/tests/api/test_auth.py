from sqlalchemy import text

CREDS = {"phone": "081200000001", "pin": "123456"}


async def test_register_then_login(client):
    r = await client.post("/auth/register", json=CREDS)
    assert r.status_code == 200 and r.json()["access_token"]
    r = await client.post("/auth/login", json=CREDS)
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
