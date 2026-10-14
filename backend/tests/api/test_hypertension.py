from tests.api.helpers import complete_profile

PROFILE = {"smoker": False, "parent_hypertension": False}


async def projection(client, headers):
    return (await client.get("/projection", headers=headers)).json()["hypertension"]


async def post_bp(client, headers, sys_, dia):
    r = await client.post("/results", json={"kind": "blood_pressure", "value": {"sys": sys_, "dia": dia},
                                            "source": "self"}, headers=headers)
    assert r.status_code == 200, r.text


async def test_without_a_bp_measurement_the_app_asks_for_one(client, auth_headers):
    await complete_profile(client, auth_headers, **PROFILE)
    h = await projection(client, auth_headers)
    assert h["status"] == "needs_bp" and h["risk_low"] is None


async def test_with_bp_and_profile_the_four_year_risk_is_a_range_or_point(client, auth_headers):
    await complete_profile(client, auth_headers, **PROFILE)
    await post_bp(client, auth_headers, 128, 82)
    h = await projection(client, auth_headers)
    assert h["status"] == "ok"
    assert 0 < h["risk_low"] <= h["risk_high"] < 1
    assert h["risk_low"] == h["risk_high"]  # merokok dan riwayat orang tua diketahui -> satu titik
    assert h["category_low"] in {"low", "medium", "high"} and h["horizon_years"] == 4


async def test_unknown_parental_history_widens_into_a_range(client, auth_headers):
    await complete_profile(client, auth_headers, smoker=False)
    await post_bp(client, auth_headers, 128, 82)
    h = await projection(client, auth_headers)
    assert h["status"] == "ok" and h["risk_low"] < h["risk_high"]


async def test_already_hypertensive_reading_is_not_scored(client, auth_headers):
    await complete_profile(client, auth_headers, **PROFILE)
    await post_bp(client, auth_headers, 150, 95)
    h = await projection(client, auth_headers)
    assert h["status"] == "already_hypertensive" and h["risk_low"] is None


async def test_people_with_diabetes_are_out_of_the_models_population(client, auth_headers):
    await complete_profile(client, auth_headers, **PROFILE)
    await post_bp(client, auth_headers, 120, 80)
    await client.post("/diagnoses", json={"condition": "diabetes"}, headers=auth_headers)
    assert (await projection(client, auth_headers))["status"] == "has_diabetes"


async def test_incomplete_profile_is_reported_not_crashing(client, auth_headers):
    await post_bp(client, auth_headers, 120, 80)
    assert (await projection(client, auth_headers))["status"] == "needs_profile"
