"""Bentuk keluaran proyeksi/what-if yang dipakai bersama oleh tool LLM dan endpoint HTTP."""
from app.core_calc.findrisc import ScoreRange, category
from app.core_calc.projection import projection_band
from app.core_calc.whatif import WhatIfChange, simulate
from app.services.risk import RiskState


def _range(rng: ScoreRange) -> dict:
    return {"low": rng.low, "high": rng.high}


def suggested_change(state: RiskState) -> WhatIfChange:
    """Perbaikan kebiasaan yang masuk akal untuk pengguna ini (dasar kartu 'kebiasaan paling berdampak')."""
    i = state.inputs
    return WhatIfChange(
        active_30min=True if i.active_30min is not True else None,
        daily_veg_fruit=True if i.daily_veg_fruit is not True else None,
        weight_delta_kg=-round(state.weight_kg * 0.05, 1) if state.weight_kg and i.bmi and i.bmi >= 25 else None,
        sweet_drinks_delta_per_day=-state.avg_sweet_drinks_per_day if state.avg_sweet_drinks_per_day > 0 else 0.0,
    )


def most_impactful_habit(state: RiskState) -> str:
    return whatif_payload(state, suggested_change(state))["most_impactful"]


def hypertension_payload(state: RiskState) -> dict:
    h = state.hypertension
    return {
        "status": h.status,
        "horizon_years": 4,
        "risk_low": h.risk_low,
        "risk_high": h.risk_high,
        "category_low": h.category_low,
        "category_high": h.category_high,
        "last_bp": {"sys": h.last_bp[0], "dia": h.last_bp[1]} if h.last_bp else None,
    }


def projection_payload(state: RiskState) -> dict:
    return {
        "hypertension": hypertension_payload(state),
        "score_low": state.rng.low,
        "score_high": state.rng.high,
        "category_low": state.category_low,
        "category_high": state.category_high,
        "p10_low": state.p10_low,
        "p10_high": state.p10_high,
        "curve_low": state.curve_low,
        "curve_high": state.curve_high,
        "needs_profile": state.needs_profile,
        "mode": state.mode,
        "bp_category": state.last_bp_category,
        "most_impactful": most_impactful_habit(state),
    }


def change_from_dict(raw: dict) -> WhatIfChange:
    """Ambil hanya kunci yang dikenal dan bertipe benar; sisanya diabaikan."""
    def as_bool(v):
        return v if isinstance(v, bool) else None

    def as_num(v):
        return float(v) if isinstance(v, int | float) and not isinstance(v, bool) else None

    return WhatIfChange(
        active_30min=as_bool(raw.get("active_30min")),
        daily_veg_fruit=as_bool(raw.get("daily_veg_fruit")),
        weight_delta_kg=as_num(raw.get("weight_delta_kg")),
        sweet_drinks_delta_per_day=as_num(raw.get("sweet_drinks_delta_per_day")) or 0.0,
    )


def whatif_payload(state: RiskState, change: WhatIfChange) -> dict:
    result = simulate(
        state.inputs, state.height_cm, state.weight_kg, change,
        state.avg_sweet_drinks_per_day, state.sugar_g_per_drink,
    )
    band = projection_band(result.after)
    return {
        "before": _range(result.before),
        "after": _range(result.after),
        "category_after_low": category(result.after.low),
        "category_after_high": category(result.after.high),
        "curve_after_low": band.low,
        "curve_after_high": band.high,
        "sugar_g_before": result.sugar_g_before,
        "sugar_g_after": result.sugar_g_after,
        "most_impactful": result.most_impactful,
    }
