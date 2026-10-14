from datetime import datetime, timezone

from app.repos import logs as logs_repo
from app.services.risk import compute_risk_state, record_result

BASE = dict(birth_date="1998-03-14", sex="male", height_cm=170, weight_kg=78, waist_cm=95,
            family_history_diabetes="first_degree", on_bp_medication=False, history_high_glucose=False,
            usual_veg_fruit=True)


async def test_one_activity_log_does_not_override_the_onboarding_baseline(session_maker, make_user):
    uid = await make_user(**BASE, usual_active_30min=True)
    async with session_maker() as session:
        await logs_repo.add_log(session, uid, kind="activity", source="text",
                                occurred_at=datetime.now(timezone.utc),
                                extracted={"kind": "jalan kaki", "minutes": 30}, raw_text="jalan 30 menit", items=[])
        state = await compute_risk_state(session, uid)
    assert state.inputs.active_30min is True


async def test_sweet_drink_average_uses_days_actually_covered(session_maker, make_user):
    uid = await make_user(**BASE)
    async with session_maker() as session:
        await logs_repo.add_log(session, uid, kind="drink", source="text",
                                occurred_at=datetime.now(timezone.utc),
                                extracted={"name": "es teh manis", "count": 2}, raw_text="2 es teh",
                                items=[logs_repo.ItemData(name="es teh manis", portion_g=500, sugar_g=40)])
        state = await compute_risk_state(session, uid)
    assert state.avg_sweet_drinks_per_day == 2.0  # baru satu hari tercatat, bukan dibagi 14


async def test_high_hba1c_counts_as_a_high_glucose_history(session_maker, make_user):
    uid = await make_user(**BASE)
    async with session_maker() as session:
        outcome = await record_result(session, uid, "hba1c", {"percent": 8.0}, "lab")
    assert outcome.state.inputs.history_high_glucose is True


async def test_normal_hba1c_makes_the_factor_known_false(session_maker, make_user):
    uid = await make_user(**{**BASE, "history_high_glucose": None})
    async with session_maker() as session:
        outcome = await record_result(session, uid, "hba1c", {"percent": 5.0}, "lab")
    assert outcome.state.inputs.history_high_glucose is False
