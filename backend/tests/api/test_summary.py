from datetime import datetime, timedelta, timezone

from seed.raka import RAKA_PHONE, RAKA_PIN, create_raka


async def raka_headers(client, session_maker):
    async with session_maker() as session:
        await create_raka(session)
    r = await client.post("/auth/login", json={"phone": RAKA_PHONE, "pin": RAKA_PIN})
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


async def test_doctor_summary_condenses_profile_risk_habits_and_foods(client, session_maker):
    h = await raka_headers(client, session_maker)
    await client.post("/results", json={"kind": "blood_pressure", "value": {"sys": 128, "dia": 82}, "source": "self"},
                      headers=h)
    r = await client.get("/summary/doctor?days=30", headers=h)
    assert r.status_code == 200
    s = r.json()
    assert s["period_days"] == 30
    assert s["patient"]["name"] == "Raka" and s["patient"]["sex"] == "male"
    assert s["risk"]["diabetes"]["category_low"] and s["risk"]["hypertension"]["status"] == "ok"
    assert s["habits"]["days_logged"] >= 14
    assert s["habits"]["sleep_hours_avg"] == 5.0
    assert s["habits"]["sweet_drinks_per_day"] > 0
    assert s["top_foods"] and s["top_foods"][0]["count"] >= s["top_foods"][-1]["count"]
    assert [x["kind"] for x in s["clinical_results"]] == ["blood_pressure"]
    text = s["text"]
    assert "Raka" in text and "bukan diagnosis" in text.lower() and "FINDRISC" in text


async def test_doctor_summary_for_a_new_user_does_not_crash(client, auth_headers):
    s = (await client.get("/summary/doctor", headers=auth_headers)).json()
    assert s["habits"]["days_logged"] == 0 and s["top_foods"] == [] and s["clinical_results"] == []
    assert "belum ada catatan" in s["text"].lower()


async def test_doctor_summary_requires_login_and_valid_period(client, auth_headers):
    assert (await client.get("/summary/doctor")).status_code == 401
    assert (await client.get("/summary/doctor?days=0", headers=auth_headers)).status_code == 422
    assert (await client.get("/summary/doctor?days=365", headers=auth_headers)).status_code == 422


async def add_meal(session, uid, name, sugar, when):
    from app.repos import logs as logs_repo

    await logs_repo.add_log(session, uid, kind="meal", source="text", occurred_at=when,
                            extracted={"items": [{"name": name}]}, raw_text=name,
                            items=[logs_repo.ItemData(name=name, sugar_g=sugar)])


async def test_food_glucose_correlation_needs_enough_paired_readings(client, auth_headers, session_maker):
    from sqlalchemy import text

    async with session_maker() as s:
        uid = (await s.execute(text("select id from users limit 1"))).scalar_one()
        now = datetime.now(timezone.utc)
        for i, mg in enumerate((150, 160, 170)):
            t = now - timedelta(days=i + 1)
            await add_meal(s, uid, "nasi goreng", 2, t - timedelta(hours=1))
            await s.execute(text("insert into clinical_results (user_id, kind, value, measured_at, source) "
                                 "values (:u, 'random_glucose', cast(:v as jsonb), :t, 'self')"),
                            {"u": uid, "v": '{"mg_dl": %d}' % mg, "t": t})
        await add_meal(s, uid, "gado gado", 3, now - timedelta(days=9, hours=1))
        await s.execute(text("insert into clinical_results (user_id, kind, value, measured_at, source) "
                             "values (:u, 'random_glucose', cast(:v as jsonb), :t, 'self')"),
                        {"u": uid, "v": '{"mg_dl": 120}', "t": now - timedelta(days=9)})
        await s.commit()
    body = (await client.get("/insights/food-glucose", headers=auth_headers)).json()
    assert body["total_readings"] == 4
    foods = {f["name"]: f for f in body["foods"]}
    assert foods["nasi goreng"]["samples"] == 3 and foods["nasi goreng"]["avg_mg_dl"] == 160
    assert "gado gado" not in foods  # baru 1 sampel: belum cukup
    assert "bukan" in body["disclaimer"].lower()


async def test_food_glucose_without_readings_says_more_data_is_needed(client, auth_headers):
    body = (await client.get("/insights/food-glucose", headers=auth_headers)).json()
    assert body["foods"] == [] and body["needs_more_data"] is True and body["total_readings"] == 0
