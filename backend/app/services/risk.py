"""Merakit input FINDRISC dari profil + log + hasil cek, lalu menghitung proyeksi.

Semua angka berasal dari core_calc; modul ini hanya menyambungkan data pengguna ke fungsi murni itu.
"""
import uuid
from dataclasses import asdict, dataclass
from datetime import datetime

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.bp import bp_category, validate_glucose
from app.core_calc.check_trigger import CheckRecommendation as CheckRec
from app.core_calc.check_trigger import evaluate_check
from app.core_calc.constants import GLUCOSE_HIGH_FASTING, GLUCOSE_HIGH_HBA1C, GLUCOSE_HIGH_RANDOM
from app.core_calc import framingham
from app.core_calc.findrisc import FindriscInputs, ScoreRange, category, p10, score_range
from app.core_calc.projection import projection_band
from app.core_calc.red_flags import RedFlag, detect_red_flags
from app.models import CheckRecommendation, ClinicalResult, Diagnosis, HealthProfile, RiskSnapshot, User
from app.repos import logs as logs_repo
from app.services import check_followup
from app.repos.profiles import age_from
from app.timeutil import local_date, utcnow

VEG_FRUIT_FOOD_IDS = {
    "sayur_asem", "sayur_sop", "tumis_kangkung", "capcay", "gado_gado", "pecel", "lalapan", "urap",
    "sayur_lodeh", "karedok", "gulai_nangka", "pisang", "apel", "jeruk", "semangka", "pepaya",
    "mangga", "salak", "melon", "anggur", "alpukat",
}
ACTIVE_MINUTES_PER_DAY = 30
VEG_FRUIT_DAY_SHARE = 0.7
MIN_LOGGED_DAYS = 3
SWEET_DRINK_MIN_SUGAR_G = 8.0
DEFAULT_SUGAR_PER_DRINK = 20.0
WINDOW_DAYS = 14
GLUCOSE_KINDS = {"fasting_glucose", "random_glucose", "hba1c"}


@dataclass
class HypertensionRisk:
    """Risiko hipertensi 4 tahun (Framingham). status: ok, needs_bp, needs_profile, already_hypertensive,
    out_of_age_range, has_diabetes."""

    status: str
    risk_low: float | None = None
    risk_high: float | None = None
    category_low: str | None = None
    category_high: str | None = None
    last_bp: tuple[int, int] | None = None


@dataclass
class RiskState:
    inputs: FindriscInputs
    rng: ScoreRange
    category_low: str
    category_high: str
    p10_low: float
    p10_high: float
    curve_low: list[float]
    curve_high: list[float]
    needs_profile: bool
    glucose_known: bool
    bp_known: bool
    habits_worsening: bool
    avg_sweet_drinks_per_day: float
    sugar_g_per_drink: float
    height_cm: float | None
    weight_kg: float | None
    mode: str
    last_bp_category: str | None
    hypertension: HypertensionRisk


@dataclass
class ResultOutcome:
    red_flag: RedFlag | None
    state: RiskState
    saved: bool
    bp_category: str | None = None
    result_id: uuid.UUID | None = None


def _glucose_flag(profile: HealthProfile | None, results: list[ClinicalResult]) -> bool | None:
    if profile is not None and profile.history_high_glucose:
        return True
    measured = [r for r in results if r.kind in {"fasting_glucose", "random_glucose", "hba1c"}]
    if measured:
        high = any(
            (r.kind == "fasting_glucose" and r.value.get("mg_dl", 0) >= GLUCOSE_HIGH_FASTING)
            or (r.kind == "random_glucose" and r.value.get("mg_dl", 0) >= GLUCOSE_HIGH_RANDOM)
            or (r.kind == "hba1c" and r.value.get("percent", 0) >= GLUCOSE_HIGH_HBA1C)
            for r in measured
        )
        return high
    return profile.history_high_glucose if profile is not None else None


def _covered_days(recent: list) -> int:
    """Berapa hari yang benar-benar tercakup log (maks. WINDOW_DAYS); pembagi rata-rata harian."""
    if not recent:
        return 1
    earliest = min(log.occurred_at for log, _ in recent)
    return max(1, min(WINDOW_DAYS, (utcnow() - earliest).days + 1))


def _activity_flag(profile: HealthProfile | None, recent: list) -> bool | None:
    baseline = profile.usual_active_30min if profile is not None else None
    covered = _covered_days(recent)
    has_activity_logs = any(log.kind == "activity" for log, _ in recent)
    # Log baru belum cukup mewakili kebiasaan: pakai baseline onboarding sampai ada beberapa hari log.
    if not has_activity_logs or covered < MIN_LOGGED_DAYS:
        return baseline
    minutes = sum(float(log.extracted.get("minutes", 0) or 0) for log, _ in recent if log.kind == "activity")
    return minutes / covered >= ACTIVE_MINUTES_PER_DAY


def _veg_fruit_flag(profile: HealthProfile | None, recent: list) -> bool | None:
    meal_days: dict = {}
    for log, items in recent:
        if log.kind != "meal":
            continue
        day = local_date(log.occurred_at)
        meal_days.setdefault(day, False)
        if any(i.food_id in VEG_FRUIT_FOOD_IDS for i in items):
            meal_days[day] = True
    if len(meal_days) >= MIN_LOGGED_DAYS:
        return sum(meal_days.values()) / len(meal_days) >= VEG_FRUIT_DAY_SHARE
    return profile.usual_veg_fruit if profile is not None else None


def _sweet_drink_stats(recent: list) -> tuple[float, float]:
    count_total, sugar_total = 0.0, 0.0
    for log, items in recent:
        if log.kind != "drink" or not items:
            continue
        count = float(log.extracted.get("count", 1) or 1)
        sugar = sum(float(i.sugar_g or 0) for i in items)
        if sugar / count >= SWEET_DRINK_MIN_SUGAR_G:
            count_total += count
            sugar_total += sugar
    if count_total == 0:
        return 0.0, DEFAULT_SUGAR_PER_DRINK
    return count_total / _covered_days(recent), sugar_total / count_total


def _habits_worsening(recent: list) -> bool:
    now = utcnow()
    sugar = {"this": 0.0, "prev": 0.0}
    for log, items in recent:
        if log.kind not in {"meal", "drink"}:
            continue
        bucket = "this" if (now - log.occurred_at).days < 7 else "prev"
        sugar[bucket] += sum(float(i.sugar_g or 0) for i in items)
    return sugar["prev"] > 0 and sugar["this"] > sugar["prev"] * 1.25


def _hypertension_risk(profile: HealthProfile | None, bp_results: list, bmi: float | None, has_diabetes: bool) -> HypertensionRisk:
    if not bp_results:
        return HypertensionRisk("needs_bp")
    v = bp_results[0].value
    bp = (int(v["sys"]), int(v["dia"]))
    age = age_from(profile.birth_date) if profile else None
    if profile is None or age is None or profile.sex is None or bmi is None:
        return HypertensionRisk("needs_profile", last_bp=bp)
    reason = framingham.eligibility(age=age, sbp=bp[0], dbp=bp[1], has_diabetes=has_diabetes)
    if reason is not None:
        return HypertensionRisk(reason, last_bp=bp)
    parental = {True: (1, 2), False: (0,), None: (0, 1, 2)}[profile.parent_hypertension]
    low, high = framingham.risk_range(
        age=age, female=profile.sex == "female", sbp=bp[0], dbp=bp[1], bmi=bmi,
        smoker=profile.smoker, parental_options=parental,
    )
    return HypertensionRisk("ok", low, high, framingham.category(low), framingham.category(high), bp)


async def compute_risk_state(session: AsyncSession, user_id: uuid.UUID) -> RiskState:
    user = await session.get(User, user_id)
    profile = await session.get(HealthProfile, user_id)
    results = list(
        (await session.execute(
            select(ClinicalResult).where(ClinicalResult.user_id == user_id).order_by(ClinicalResult.measured_at.desc())
        )).scalars().all()
    )
    recent = await logs_repo.since(session, user_id, days=WINDOW_DAYS)

    height = profile.height_cm if profile else None
    weight = profile.weight_kg if profile else None
    bmi = round(weight / (height / 100) ** 2, 1) if height and weight else None
    waist = profile.waist_cm if profile else None
    if waist is None:
        waist = next((r.value.get("cm") for r in results if r.kind == "waist"), None)
    bp_results = [r for r in results if r.kind == "blood_pressure"]
    has_diabetes = (
        await session.execute(
            select(Diagnosis.id).where(Diagnosis.user_id == user_id, Diagnosis.condition == "diabetes").limit(1)
        )
    ).first() is not None

    inputs = FindriscInputs(
        age=age_from(profile.birth_date) if profile else None,
        bmi=bmi,
        sex=profile.sex if profile else None,
        waist_cm=waist,
        active_30min=_activity_flag(profile, recent),
        daily_veg_fruit=_veg_fruit_flag(profile, recent),
        on_bp_medication=profile.on_bp_medication if profile else None,
        history_high_glucose=_glucose_flag(profile, results),
        family_history=profile.family_history_diabetes if profile else None,
    )
    rng = score_range(inputs)
    band = projection_band(rng)
    avg_drinks, sugar_per_drink = _sweet_drink_stats(recent)
    last_bp = None
    if bp_results:
        v = bp_results[0].value
        last_bp = bp_category(int(v["sys"]), int(v["dia"]))
    return RiskState(
        inputs=inputs,
        rng=rng,
        category_low=category(rng.low),
        category_high=category(rng.high),
        p10_low=p10(rng.low),
        p10_high=p10(rng.high),
        curve_low=band.low,
        curve_high=band.high,
        needs_profile=profile is None
        or any(v is None for v in (profile.birth_date, profile.sex, profile.height_cm, profile.weight_kg)),
        glucose_known=any(r.kind in GLUCOSE_KINDS for r in results),
        bp_known=bool(bp_results),
        habits_worsening=_habits_worsening(recent),
        avg_sweet_drinks_per_day=avg_drinks,
        sugar_g_per_drink=sugar_per_drink,
        height_cm=height,
        weight_kg=weight,
        mode=user.mode if user else "prevention",
        last_bp_category=last_bp,
        hypertension=_hypertension_risk(profile, bp_results, bmi, has_diabetes),
    )


async def save_snapshot(session: AsyncSession, user_id: uuid.UUID, state: RiskState, *, commit: bool = True) -> None:
    session.add(
        RiskSnapshot(
            user_id=user_id, model="findrisc", score_low=state.rng.low, score_high=state.rng.high,
            category_low=state.category_low, category_high=state.category_high,
            inputs=asdict(state.inputs),
        )
    )
    if commit:
        await session.commit()


async def open_recommendations(session: AsyncSession, user_id: uuid.UUID) -> list[CheckRecommendation]:
    stmt = (
        select(CheckRecommendation)
        .where(CheckRecommendation.user_id == user_id, CheckRecommendation.status == "open")
        .order_by(CheckRecommendation.created_at.desc())
    )
    return list((await session.execute(stmt)).scalars().all())


async def refresh_check_recommendation(
    session: AsyncSession, user_id: uuid.UUID, state: RiskState | None = None, *, commit: bool = True
) -> CheckRec | None:
    state = state or await compute_risk_state(session, user_id)
    rec = evaluate_check(state.rng, state.glucose_known, state.bp_known, state.habits_worsening)
    open_rows = await open_recommendations(session, user_id)
    keep = None
    for row in open_rows:
        if rec is not None and row.test_kind == rec.test_kind and keep is None:
            row.reason, keep = rec.reason, row
        else:
            row.status = "dismissed"
    if rec is not None and keep is None:
        # Jangan menagih lagi tepat setelah pengguna menjawab "sudah dicek" atau "tidak perlu".
        held = await check_followup.held_rows(session, user_id)
        if not check_followup.is_held(held, rec.test_kind):
            session.add(CheckRecommendation(user_id=user_id, test_kind=rec.test_kind, reason=rec.reason))
    if commit:
        await session.commit()
    return rec


def _validate(kind: str, value: dict) -> tuple[RedFlag | None, str | None]:
    """Validasi nilai hasil cek; ValueError bila mustahil. Mengembalikan (red_flag, kategori_tensi)."""
    try:
        if kind in {"fasting_glucose", "random_glucose"}:
            mg = validate_glucose(float(value["mg_dl"]))
            return detect_red_flags(glucose_mg_dl=mg), None
        if kind == "blood_pressure":
            sys_, dia = int(value["sys"]), int(value["dia"])
            return detect_red_flags(bp=(sys_, dia)), bp_category(sys_, dia)
        if kind == "hba1c":
            if not 3.0 <= float(value["percent"]) <= 20.0:
                raise ValueError("HbA1c tidak masuk akal")
            return None, None
        if kind == "waist":
            if not 30.0 <= float(value["cm"]) <= 250.0:
                raise ValueError("lingkar perut tidak masuk akal")
            return None, None
    except (KeyError, TypeError) as exc:
        raise ValueError(f"nilai hasil cek tidak lengkap untuk {kind}") from exc
    raise ValueError(f"jenis hasil cek tidak dikenal: {kind}")


async def record_result(
    session: AsyncSession,
    user_id: uuid.UUID,
    kind: str,
    value: dict,
    source: str,
    measured_at: datetime | None = None,
    *,
    commit: bool = True,
) -> ResultOutcome:
    """Simpan hasil cek lalu hitung ulang proyeksi.

    Nilai mustahil -> ValueError (tidak disimpan). Nilai berbahaya -> red_flag dikembalikan dan hasil
    TIDAK disimpan otomatis (bisa salah baca); pengguna diarahkan ke fasilitas kesehatan.
    """
    flag, bp_cat = _validate(kind, value)
    if flag is not None:
        return ResultOutcome(flag, await compute_risk_state(session, user_id), saved=False, bp_category=bp_cat)

    result = ClinicalResult(user_id=user_id, kind=kind, value=value, source=source, measured_at=measured_at or utcnow())
    session.add(result)
    await session.flush()
    satisfied = "blood_pressure" if kind == "blood_pressure" else "fasting_glucose"
    for row in await open_recommendations(session, user_id):
        if row.test_kind == satisfied and (kind != "waist"):
            row.status = "done"
    state = await compute_risk_state(session, user_id)
    await save_snapshot(session, user_id, state, commit=False)
    await refresh_check_recommendation(session, user_id, state, commit=False)
    if commit:
        await session.commit()
    return ResultOutcome(None, state, saved=True, bp_category=bp_cat, result_id=result.id)
