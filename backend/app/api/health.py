"""Endpoint keadaan kesehatan: target, proyeksi, rekomendasi cek, hasil cek, diagnosis, faskes."""
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.heart_rate import classify_resting
from app.core_calc.red_flags import RedFlag
from app.db import get_session
from app.models import Diagnosis, User, WhatIfScenario
from app.services import faskes_lookup
from app.schemas.api import CheckRespondIn, DiagnosisIn, ResultIn, ScenarioIn, WhatIfIn
from app.security import current_user_id
from app.services import check_followup, idempotency, risk
from app.services.projection_view import projection_payload, whatif_payload
from app.services.targets_view import today_targets
from app.core_calc.whatif import WhatIfChange

router = APIRouter(tags=["health"])


def _flag(flag: RedFlag | None) -> dict | None:
    return {"kind": flag.kind, "message": flag.message} if flag else None


@router.get("/targets/today")
async def targets_today(
    user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    return await today_targets(session, user_id)


@router.get("/projection")
async def projection(
    user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    return projection_payload(await risk.compute_risk_state(session, user_id))


@router.post("/projection/whatif")
async def projection_whatif(
    body: WhatIfIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    state = await risk.compute_risk_state(session, user_id)
    return whatif_payload(state, WhatIfChange(**body.model_dump(exclude_none=True)))


MAX_SCENARIOS = 10


def _params(body: WhatIfIn) -> dict:
    return body.model_dump(exclude_none=True)


def _scenario_out(row: WhatIfScenario, state) -> dict:
    now = whatif_payload(state, WhatIfChange(**row.params))
    return {
        "id": str(row.id), "name": row.name, "params": row.params, "saved_at": row.created_at.isoformat(),
        "saved": {"before": row.saved_before, "after": row.saved_after},
        # Dihitung ulang dengan data terkini: skenario yang sama bisa berubah hasilnya saat datamu berubah.
        "now": {"before": now["before"], "after": now["after"], "category_after_low": now["category_after_low"],
                "category_after_high": now["category_after_high"]},
    }


@router.get("/projection/scenarios")
async def list_scenarios(
    user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    rows = (
        await session.execute(
            select(WhatIfScenario).where(WhatIfScenario.user_id == user_id).order_by(WhatIfScenario.created_at.desc())
        )
    ).scalars().all()
    state = await risk.compute_risk_state(session, user_id)
    return {"scenarios": [_scenario_out(r, state) for r in rows], "max": MAX_SCENARIOS}


@router.post("/projection/scenarios")
async def save_scenario(
    body: ScenarioIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    count = (
        await session.execute(select(func.count()).select_from(WhatIfScenario).where(WhatIfScenario.user_id == user_id))
    ).scalar_one()
    if count >= MAX_SCENARIOS:
        raise HTTPException(409, f"Sudah ada {MAX_SCENARIOS} skenario tersimpan. Hapus satu dulu.")
    params = _params(WhatIfIn(**body.model_dump(exclude={"name"})))
    meaningful = (
        params.get("active_30min") is not None
        or params.get("daily_veg_fruit") is not None
        or bool(params.get("weight_delta_kg"))
        or bool(params.get("sweet_drinks_delta_per_day"))
    )
    if not meaningful:
        raise HTTPException(422, "Skenario kosong. Geser setidaknya satu kebiasaan dulu.")
    state = await risk.compute_risk_state(session, user_id)
    result = whatif_payload(state, WhatIfChange(**params))
    row = WhatIfScenario(
        user_id=user_id, name=body.name, params=params, saved_before=result["before"], saved_after=result["after"]
    )
    session.add(row)
    await session.commit()
    await session.refresh(row)
    return _scenario_out(row, state)


@router.delete("/projection/scenarios/{scenario_id}")
async def delete_scenario(
    scenario_id: uuid.UUID, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    row = await session.get(WhatIfScenario, scenario_id)
    if row is None or row.user_id != user_id:
        raise HTTPException(404, "Skenario tidak ditemukan")
    await session.delete(row)
    await session.commit()
    return {"ok": True}


@router.get("/recommendations/check")
async def check_recommendation(
    user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict | None:
    await risk.refresh_check_recommendation(session, user_id)
    rows = await risk.open_recommendations(session, user_id)
    if not rows:
        return None
    row = rows[0]
    return {"id": str(row.id), "test_kind": row.test_kind, "reason": row.reason,
            "created_at": row.created_at.isoformat(),
            "age_days": check_followup.age_days(row),
            "follow_up": check_followup.follow_up_due(row)}


@router.post("/recommendations/{rec_id}/respond")
async def respond_to_check(
    rec_id: uuid.UUID,
    body: CheckRespondIn,
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Jawaban atas 'sudah dicek?': done (sudah), snooze (nanti, tanya lagi 3 hari), dismiss (tidak perlu, ditahan 30 hari)."""
    out = await check_followup.respond(session, user_id, rec_id, body.action)
    if out is None:
        raise HTTPException(404, "Rekomendasi tidak ditemukan atau sudah ditutup")
    return out


@router.post("/results")
async def post_result(
    body: ResultIn,
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
    key: str | None = Depends(idempotency.idempotency_key),
) -> dict:
    stored = await idempotency.replay(session, user_id, key)
    if stored is not None:
        return stored
    try:
        outcome = await risk.record_result(
            session, user_id, body.kind, body.value, body.source, body.measured_at
        )
    except ValueError as exc:
        await session.rollback()
        raise HTTPException(422, str(exc)) from None
    out = {
        "saved": outcome.saved,
        "red_flag": _flag(outcome.red_flag),
        "bp_category": outcome.bp_category,
        "hr_range": classify_resting(body.value["bpm"]) if body.kind == "resting_heart_rate" and outcome.saved else None,
        "projection": projection_payload(outcome.state),
    }
    await idempotency.remember(session, user_id, key, out)
    return out


@router.post("/diagnoses")
async def post_diagnosis(
    body: DiagnosisIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    session.add(Diagnosis(user_id=user_id, condition=body.condition, diagnosed_at=body.diagnosed_at,
                          confirmed_by=body.confirmed_by))
    user = await session.get(User, user_id)
    user.mode = "management"
    await session.commit()
    return {"mode": "management", "condition": body.condition}


@router.get("/faskes/nearby")
async def faskes_nearby(
    lat: float = Query(ge=-90, le=90),
    lng: float = Query(ge=-180, le=180),
    _: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    return await faskes_lookup.nearby(session, lat, lng)
