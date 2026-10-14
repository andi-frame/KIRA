async def test_profile_requires_token(client):
    assert (await client.get("/profile")).status_code == 401
    assert (await client.get("/profile", headers={"Authorization": "Bearer nonsense"})).status_code == 401


async def test_put_then_get_roundtrip(client, auth_headers):
    body = {"birth_date": "1998-03-14", "sex": "male", "height_cm": 170, "weight_kg": 78,
            "family_history_diabetes": "first_degree", "smoker": False}
    r = await client.put("/profile", json=body, headers=auth_headers)
    assert r.status_code == 200
    got = (await client.get("/profile", headers=auth_headers)).json()
    assert got["sex"] == "male" and got["height_cm"] == 170 and got["family_history_diabetes"] == "first_degree"
    assert got["mode"] == "prevention" and got["waist_cm"] is None
    assert got["age"] >= 27


async def test_partial_update_keeps_existing_fields(client, auth_headers):
    await client.put("/profile", json={"sex": "female", "height_cm": 160}, headers=auth_headers)
    await client.put("/profile", json={"weight_kg": 55}, headers=auth_headers)
    got = (await client.get("/profile", headers=auth_headers)).json()
    assert (got["sex"], got["height_cm"], got["weight_kg"]) == ("female", 160, 55)


async def test_implausible_values_rejected(client, auth_headers):
    assert (await client.put("/profile", json={"height_cm": 5}, headers=auth_headers)).status_code == 422
    assert (await client.put("/profile", json={"sex": "x"}, headers=auth_headers)).status_code == 422


async def test_empty_profile_get_returns_blank_fields_not_error(client, auth_headers):
    r = await client.get("/profile", headers=auth_headers)
    assert r.status_code == 200 and r.json()["birth_date"] is None
