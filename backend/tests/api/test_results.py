import pytest
from sqlalchemy import text

from tests.api.helpers import complete_profile, install_models, reset_models


async def count(engine, table):
    async with engine.connect() as conn:
        return (await conn.execute(text(f"select count(*) from {table}"))).scalar_one()


async def test_glucose_result_narrows_range_and_closes_recommendation(client, auth_headers):
    await complete_profile(client, auth_headers)
    before = (await client.get("/projection", headers=auth_headers)).json()
    assert (await client.get("/recommendations/check", headers=auth_headers)).json()["test_kind"] == "fasting_glucose"

    r = await client.post("/results", json={"kind": "fasting_glucose", "value": {"mg_dl": 110}, "source": "lab"},
                          headers=auth_headers)
    assert r.status_code == 200 and r.json()["saved"] is True and r.json()["red_flag"] is None
    after = r.json()["projection"]
    assert (after["score_high"] - after["score_low"]) < (before["score_high"] - before["score_low"])
    rec = (await client.get("/recommendations/check", headers=auth_headers)).json()
    assert rec is None or rec["test_kind"] != "fasting_glucose"


async def test_blood_pressure_result_returns_category(client, auth_headers):
    r = await client.post("/results", json={"kind": "blood_pressure", "value": {"sys": 135, "dia": 85}, "source": "self"},
                          headers=auth_headers)
    assert r.status_code == 200 and r.json()["bp_category"] == "prehypertension"


async def test_implausible_results_rejected_and_not_stored(client, auth_headers, engine):
    for payload in (
        {"kind": "fasting_glucose", "value": {"mg_dl": 5000}},
        {"kind": "fasting_glucose", "value": {"mg_dl": 5}},
        {"kind": "blood_pressure", "value": {"sys": 400, "dia": 80}},
        {"kind": "blood_pressure", "value": {"sys": 120}},
        {"kind": "mood", "value": {"x": 1}},
    ):
        r = await client.post("/results", json={**payload, "source": "self"}, headers=auth_headers)
        assert r.status_code == 422, payload
    assert await count(engine, "clinical_results") == 0


async def test_dangerous_glucose_returns_red_flag_and_is_not_auto_saved(client, auth_headers, engine):
    r = await client.post("/results", json={"kind": "fasting_glucose", "value": {"mg_dl": 45}, "source": "self"},
                          headers=auth_headers)
    assert r.status_code == 200
    assert r.json()["red_flag"]["kind"] == "glucose_low" and r.json()["saved"] is False
    assert await count(engine, "clinical_results") == 0


async def test_diagnosis_switches_to_management_mode(client, auth_headers):
    r = await client.post("/diagnoses", json={"condition": "prediabetes", "confirmed_by": "dokter umum"},
                          headers=auth_headers)
    assert r.status_code == 200
    assert (await client.get("/profile", headers=auth_headers)).json()["mode"] == "management"
    bad = await client.post("/diagnoses", json={"condition": "flu"}, headers=auth_headers)
    assert bad.status_code == 422


async def test_patch_log_recomputes_items_and_marks_corrected(client, auth_headers):
    install_models()
    try:
        chat = (await client.post("/chat/message", json={"text": "makan rendang"}, headers=auth_headers)).json()
    finally:
        reset_models()
    logs = (await client.get("/logs", headers=auth_headers)).json()["logs"]
    meal = next(lg for lg in logs if lg["kind"] == "meal")
    assert meal["items"][0]["fat_g"] == pytest.approx(7.9 * 0.7) and meal["corrected"] is False

    r = await client.patch(f"/logs/{meal['id']}", json={"items": [{"name": "rendang", "portion_g": 35}]},
                           headers=auth_headers)
    assert r.status_code == 200
    assert r.json()["corrected"] is True and r.json()["items"][0]["fat_g"] == pytest.approx(7.9 * 0.35)
    assert chat["log_ids"]


async def test_other_users_logs_are_invisible(client, auth_headers):
    install_models()
    try:
        await client.post("/chat/message", json={"text": "makan rendang"}, headers=auth_headers)
    finally:
        reset_models()
    meal = next(lg for lg in (await client.get("/logs", headers=auth_headers)).json()["logs"] if lg["kind"] == "meal")

    other = await client.post("/auth/register", json={"phone": "081200000099", "pin": "654321"})
    other_headers = {"Authorization": f"Bearer {other.json()['access_token']}"}
    assert (await client.patch(f"/logs/{meal['id']}", json={"items": []}, headers=other_headers)).status_code == 404
    assert (await client.get("/logs", headers=other_headers)).json()["logs"] == []


async def test_logs_filter_by_date(client, auth_headers):
    install_models()
    try:
        await client.post("/chat/message", json={"text": "makan rendang"}, headers=auth_headers)
    finally:
        reset_models()
    assert (await client.get("/logs?date=2001-01-01", headers=auth_headers)).json()["logs"] == []
    assert (await client.get("/logs?date=not-a-date", headers=auth_headers)).status_code == 422


async def test_koreksi_porsi_log_dari_label_menskalakan_angka_tercetak(client, auth_headers):
    label = {"items": [], "drinks": [], "intent": "log",
             "label": {"product_name": "Teh Kotak", "is_drink": True, "basis": "per_serving", "serving_g": 250,
                       "servings_consumed": 1, "sugar_g": 24, "sodium_mg": 50, "fat_g": 0, "kcal": 100}}
    install_models(extract=label)
    png = b"\x89PNG\r\n\x1a\n" + b"0" * 32
    try:
        await client.post("/chat/photo?kind=label", files={"image": ("l.png", png, "image/png")}, headers=auth_headers)
    finally:
        reset_models()
    drink = next(lg for lg in (await client.get("/logs", headers=auth_headers)).json()["logs"] if lg["kind"] == "drink")
    assert drink["source"] == "photo_label" and drink["items"][0]["sugar_g"] == 24

    r = await client.patch(f"/logs/{drink['id']}", json={"items": [{"name": "Teh Kotak", "portion_g": 125}]},
                           headers=auth_headers)
    assert r.status_code == 200
    item = r.json()["items"][0]
    assert item["sugar_g"] == pytest.approx(12) and item["kcal"] == pytest.approx(50) and item["portion_g"] == 125
