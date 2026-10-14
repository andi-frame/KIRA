from datetime import timedelta

from seed.raka import RAKA_PHONE, RAKA_PIN, create_raka
from app.timeutil import local_date, utcnow


async def login_raka(client, session_maker):
    async with session_maker() as session:
        await create_raka(session)
    resp = await client.post("/auth/login", json={"phone": RAKA_PHONE, "pin": RAKA_PIN})
    assert resp.status_code == 200
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}


async def test_seed_is_idempotent(client, session_maker):
    async with session_maker() as session:
        first = await create_raka(session)
        second = await create_raka(session)
    assert first == second


async def test_raka_has_three_weeks_of_history(client, session_maker):
    headers = await login_raka(client, session_maker)
    yesterday = local_date(utcnow() - timedelta(days=1)).isoformat()
    logs = (await client.get(f"/logs?date={yesterday}", headers=headers)).json()["logs"]
    assert {lg["kind"] for lg in logs} >= {"meal", "drink", "sleep"}
    long_ago = local_date(utcnow() - timedelta(days=20)).isoformat()
    assert (await client.get(f"/logs?date={long_ago}", headers=headers)).json()["logs"]
    today = (await client.get("/logs", headers=headers)).json()["logs"]
    assert today == []  # hari ini kosong: check-in live di panggung


async def test_full_demo_flow_projection_whatif_check_calibrate_manage(client, session_maker):
    headers = await login_raka(client, session_maker)

    proj = (await client.get("/projection", headers=headers)).json()
    assert proj["needs_profile"] is False
    assert proj["score_high"] - proj["score_low"] >= 8  # rentang lebar: gula darah & lingkar perut belum diketahui
    assert proj["category_low"] != proj["category_high"]

    whatif = (await client.post("/projection/whatif",
                                json={"sweet_drinks_delta_per_day": -1, "active_30min": True}, headers=headers)).json()
    assert whatif["after"]["high"] < whatif["before"]["high"]
    assert whatif["sugar_g_after"] < whatif["sugar_g_before"]
    assert whatif["most_impactful"] in {"activity", "sweet_drinks"}

    rec = (await client.get("/recommendations/check", headers=headers)).json()
    assert rec["test_kind"] == "fasting_glucose"

    result = (await client.post("/results", json={"kind": "fasting_glucose", "value": {"mg_dl": 108},
                                                  "source": "lab"}, headers=headers)).json()
    after = result["projection"]
    assert result["saved"] is True
    assert (after["score_high"] - after["score_low"]) < (proj["score_high"] - proj["score_low"])
    assert after["score_low"] > proj["score_low"]

    assert (await client.post("/diagnoses", json={"condition": "prediabetes"}, headers=headers)).status_code == 200
    assert (await client.get("/profile", headers=headers)).json()["mode"] == "management"
    targets = (await client.get("/targets/today", headers=headers)).json()
    assert targets["mode"] == "management"
    assert targets["remaining"]["sugar_g"] < targets["limits"]["sugar_g"]
