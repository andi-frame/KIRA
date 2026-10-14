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
