from datetime import datetime, timezone

import pytest

from app.core_calc.constants import DAILY_LIMITS
from app.repos import logs as logs_repo
from app.tools import TOOLS
from app.tools.faskes import cari_faskes
from app.tools.nutrition import cari_gizi
from app.tools.risk import hitung_risiko
from app.tools.targets import sisa_target_harian
from app.tools.whatif import simulasi_whatif


def cfg(user_id, session_maker):
    return {"configurable": {"user_id": str(user_id), "session_factory": session_maker}}


async def add_sugary_drink(session_maker, user_id, sugar_g):
    async with session_maker() as session:
        await logs_repo.add_log(
            session, user_id, kind="drink", source="text", occurred_at=datetime.now(timezone.utc),
            extracted={"name": "es teh manis", "count": 1}, raw_text="es teh",
            items=[logs_repo.ItemData(name="es teh manis", portion_g=250, sugar_g=sugar_g,
                                      sodium_mg=5, fat_g=0, kcal=80)],
        )


def test_no_tool_exposes_user_id_to_the_llm():
    for t in TOOLS:
        assert "user_id" not in t.args_schema.model_json_schema().get("properties", {}), t.name


async def test_cari_gizi_scales_with_default_portion(session_maker, make_user):
    uid = await make_user()
    out = await cari_gizi.ainvoke({"makanan": "rendang"}, config=cfg(uid, session_maker))
    assert out["found"] is True and out["portion_g"] == 70
    assert out["fat_g"] == pytest.approx(14.0)


async def test_cari_gizi_unknown_food_is_not_found(session_maker, make_user):
    uid = await make_user()
    out = await cari_gizi.ainvoke({"makanan": "xyzxyz"}, config=cfg(uid, session_maker))
    assert out == {"found": False}


async def test_remaining_targets_only_count_this_users_logs(session_maker, make_user):
    a, b = await make_user(), await make_user()
    await add_sugary_drink(session_maker, a, sugar_g=20)
    out_a = await sisa_target_harian.ainvoke({}, config=cfg(a, session_maker))
    out_b = await sisa_target_harian.ainvoke({}, config=cfg(b, session_maker))
    assert out_b["remaining"]["sugar_g"] == DAILY_LIMITS["sugar_g"]
    assert out_a["remaining"]["sugar_g"] == pytest.approx(DAILY_LIMITS["sugar_g"] - 20)


async def test_risk_on_empty_profile_is_widest_range_not_an_error(session_maker, make_user):
    uid = await make_user()
    out = await hitung_risiko.ainvoke({}, config=cfg(uid, session_maker))
    assert out["needs_profile"] is True
    assert (out["score_low"], out["score_high"]) == (0, 26)


async def test_whatif_tool_reports_before_and_after(session_maker, make_user):
    uid = await make_user(birth_date="1998-03-14", sex="male", height_cm=170, weight_kg=78,
                          waist_cm=95, family_history_diabetes="first_degree",
                          usual_active_30min=False, usual_veg_fruit=True,
                          on_bp_medication=False, history_high_glucose=False)
    out = await simulasi_whatif.ainvoke({"perubahan": {"active_30min": True}}, config=cfg(uid, session_maker))
    assert out["before"]["high"] - out["after"]["high"] == 2
    assert out["most_impactful"] == "activity"


async def test_whatif_tool_ignores_unknown_keys_instead_of_crashing(session_maker, make_user):
    uid = await make_user()
    out = await simulasi_whatif.ainvoke({"perubahan": {"bogus": 1}}, config=cfg(uid, session_maker))
    assert out["most_impactful"] == "none"


async def test_faskes_sorted_by_distance(session_maker, make_user):
    uid = await make_user()
    out = await cari_faskes.ainvoke({"lat": -6.8930, "lng": 107.6130}, config=cfg(uid, session_maker))
    distances = [f["distance_km"] for f in out["faskes"]]
    assert distances == sorted(distances) and distances[0] < 0.5
