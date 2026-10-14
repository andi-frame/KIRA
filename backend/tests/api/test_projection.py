from tests.api.helpers import complete_profile


async def test_projection_on_empty_profile_is_200_with_needs_profile(client, auth_headers):
    r = await client.get("/projection", headers=auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["needs_profile"] is True and (body["score_low"], body["score_high"]) == (0, 26)


async def test_projection_has_band_curves_from_zero(client, auth_headers):
    await complete_profile(client, auth_headers)
    body = (await client.get("/projection", headers=auth_headers)).json()
    assert body["needs_profile"] is False
    assert body["score_low"] < body["score_high"]
    assert len(body["curve_low"]) == 11 and body["curve_low"][0] == 0.0
    assert all(lo <= hi for lo, hi in zip(body["curve_low"], body["curve_high"]))
    assert body["most_impactful"] in {"activity", "veg_fruit", "weight", "sweet_drinks", "none"}


async def test_whatif_lowers_score_for_activity(client, auth_headers):
    await complete_profile(client, auth_headers)
    r = await client.post("/projection/whatif", json={"active_30min": True}, headers=auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["before"]["high"] - body["after"]["high"] == 2
    assert len(body["curve_after_high"]) == 11


async def test_whatif_rejects_nonsense_types(client, auth_headers):
    r = await client.post("/projection/whatif", json={"weight_delta_kg": "banyak"}, headers=auth_headers)
    assert r.status_code == 422


async def test_targets_today_for_fresh_user_is_full_budget(client, auth_headers):
    body = (await client.get("/targets/today", headers=auth_headers)).json()
    assert body["remaining"]["sugar_g"] == body["limits"]["sugar_g"]


async def test_incomplete_profile_suggests_glucose_check(client, auth_headers):
    await complete_profile(client, auth_headers)
    rec = (await client.get("/recommendations/check", headers=auth_headers)).json()
    assert rec["test_kind"] == "fasting_glucose" and rec["reason"]


async def test_faskes_nearby_sorted_by_distance(client, auth_headers):
    r = await client.get("/faskes/nearby?lat=-6.893&lng=107.613", headers=auth_headers)
    distances = [f["distance_km"] for f in r.json()["faskes"]]
    assert distances == sorted(distances) and len(distances) >= 3
    assert (await client.get("/faskes/nearby?lat=999&lng=0", headers=auth_headers)).status_code == 422
