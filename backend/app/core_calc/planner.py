"""Penyusun rencana harian dan mingguan: makan, olahraga, tidur. Fungsi murni dan deterministik.

Rencana adalah USULAN, bukan resep medis atau terapi gizi: angka energi dari AKG 2019 (Permenkes 28/2019), batas
gula/natrium/lemak dari Permenkes 30/2013, aktivitas dari WHO 2020, tidur dari AASM/SRS; pembagian per waktu makan,
defisit energi, dan tanjakan olahraga adalah asumsi KIRA (core_calc/constants.py). Hidangan dipilih dari katalog
terkurasi (gizinya dari tabel foods), tidak pernah dikarang LLM. Masukan sama -> rencana sama.
"""
import hashlib
import math
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta

from app.core_calc.constants import (
    AKG_ENERGY_KCAL,
    ENERGY_DEFAULT_KCAL,
    ENERGY_DEFICIT_KCAL,
    ENERGY_FLOOR_KCAL,
    EXERCISE_RAMP_FACTOR,
    EXERCISE_RAMP_MIN,
    EXERCISE_WEEKLY_TARGET,
    MEAL_SPLIT,
    SLEEP_CATCHUP_TARGET,
    SLEEP_TARGET_RANGE,
)
from app.core_calc.dishes import DishRecord, expand_dish
from app.core_calc.foodindex import normalize
from app.core_calc.nutrition import FoodRecord, nutrition_for

NUTRIENTS = ("kcal", "sugar_g", "sodium_mg", "fat_g")
MEAL_SLOTS = ("breakfast", "lunch", "snack", "dinner")
SLOT_LABELS = {"breakfast": "sarapan", "lunch": "makan siang", "snack": "selingan", "dinner": "makan malam"}
KCAL_TOLERANCE = 1.15  # energi boleh sedikit di atas anggaran waktu makan (asumsi KIRA); gula/natrium/lemak tidak
REPEAT_WINDOW_DAYS = 3
# Selingan dari tabel foods (buah dan umbi rebus): rendah natrium dan lemak.
SNACK_FOOD_IDS = ("pisang", "apel", "jeruk", "pepaya", "semangka", "melon", "salak", "mangga", "anggur",
                  "ubi_rebus", "jagung_rebus", "singkong_rebus")
DRINK_SUGGESTION = "air putih atau teh tanpa gula"
DISCLAIMER = ("Rencana ini usulan untuk membantu kebiasaan sehari-hari, bukan resep atau terapi gizi. Bila punya "
              "kondisi medis, ikuti arahan dokter atau ahli gizi.")


@dataclass(frozen=True)
class PlanPrefs:
    wake_time: str = "06:00"
    meal_times: dict = field(default_factory=lambda: {"breakfast": "06:30", "lunch": "12:00", "snack": "15:30",
                                                      "dinner": "18:30"})
    exercise_time: str = "17:00"
    exercise_days: tuple[int, ...] = (0, 1, 2, 3, 4)  # 0 = Senin
    exercise_kinds: tuple[str, ...] = ("jalan cepat",)
    strength_days: int = 0
    goal: str = "jaga"  # jaga | turun_berat | aktif
    dislikes: tuple[str, ...] = ()


@dataclass(frozen=True)
class PlanContext:
    user_key: str  # benih rotasi (id pengguna): rencana stabil per pengguna per hari
    limits: dict
    mode: str = "prevention"
    age: int | None = None
    sex: str | None = None
    height_cm: float | None = None
    weight_kg: float | None = None
    recent_sleep_avg: float | None = None  # rata-rata 7 malam terakhir
    recent_weekly_active: float | None = None  # rata-rata menit aktif per minggu, 2 minggu terakhir
    exercise_blocked: bool = False  # penanda tensi "perhatian" atau keluhan bahaya: jangan beri latihan baru


@dataclass(frozen=True)
class Candidate:
    id: str
    kind: str  # dish | food
    title: str
    components: tuple[dict, ...]
    totals: dict


def _hhmm(text: str) -> tuple[int, int]:
    h, m = text.split(":")
    return int(h), int(m)


def _fmt_time(minutes: int) -> str:
    minutes %= 24 * 60
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def _n(v: float) -> str:
    return f"{v:,.0f}".replace(",", ".")


# ---------- energi ----------

def bmi(height_cm: float | None, weight_kg: float | None) -> float | None:
    if not height_cm or not weight_kg:
        return None
    return weight_kg / (height_cm / 100) ** 2


def energy_target(ctx: PlanContext, goal: str = "jaga") -> dict:
    """Kebutuhan energi harian (kkal) dari AKG 2019; defisit hanya bila IMT >= 25 dan tujuannya menurunkan berat."""
    if ctx.age is None or ctx.sex not in AKG_ENERGY_KCAL or ctx.age < 19:
        return {"kcal": ENERGY_DEFAULT_KCAL, "source": "Bawaan KIRA sampai umur dan jenis kelamin diisi di Profil",
                "adjusted": False}
    table = AKG_ENERGY_KCAL[ctx.sex]
    kcal = next((e for lo, hi, e in table if lo <= ctx.age <= hi), table[-1][2])
    source = f"AKG 2019 (Permenkes 28/2019) untuk {'laki-laki' if ctx.sex == 'male' else 'perempuan'} {ctx.age} tahun"
    b = bmi(ctx.height_cm, ctx.weight_kg)
    if goal == "turun_berat" and b is not None and b >= 25:
        kcal = max(kcal - ENERGY_DEFICIT_KCAL, ENERGY_FLOOR_KCAL[ctx.sex])
        source += f", dikurangi {ENERGY_DEFICIT_KCAL} kkal karena tujuan menurunkan berat (asumsi KIRA, bukan diet medis)"
        return {"kcal": kcal, "source": source, "adjusted": True}
    return {"kcal": kcal, "source": source, "adjusted": False}


def daily_budget(ctx: PlanContext, goal: str) -> dict:
    return {"kcal": float(energy_target(ctx, goal)["kcal"]), **{k: float(ctx.limits[k]) for k in ("sugar_g", "sodium_mg", "fat_g")}}


def slot_budget(daily: dict, slot: str) -> dict:
    return {k: daily[k] * MEAL_SPLIT[slot] for k in NUTRIENTS}


# ---------- tidur ----------

def sleep_plan(ctx: PlanContext, prefs: PlanPrefs) -> dict:
    lo, hi = SLEEP_TARGET_RANGE
    if ctx.recent_sleep_avg is None or ctx.recent_sleep_avg < lo:
        hours = SLEEP_CATCHUP_TARGET
        why = ("Rata-rata tidurmu belakangan di bawah 7 jam, jadi targetnya 8 jam." if ctx.recent_sleep_avg is not None
               else "Anjuran dewasa 7-9 jam; targetnya 8 jam sampai catatan tidurmu terkumpul.")
    else:
        hours = min(hi, max(lo, round(ctx.recent_sleep_avg * 2) / 2))
        why = f"Rata-rata tidurmu {ctx.recent_sleep_avg:.1f} jam sudah cukup; pertahankan."
    h, m = _hhmm(prefs.wake_time)
    bedtime = _fmt_time(h * 60 + m - int(hours * 60))
    return {"hours": hours, "bedtime": bedtime, "wake_time": prefs.wake_time, "why": why,
            "source": "AASM/SRS (Watson dkk. 2015): dewasa 7 jam atau lebih"}


# ---------- olahraga ----------

def weekly_exercise_target(ctx: PlanContext) -> dict:
    recent = ctx.recent_weekly_active
    if recent is None or recent < EXERCISE_WEEKLY_TARGET:
        start = max(EXERCISE_RAMP_MIN, EXERCISE_RAMP_FACTOR * (recent or 0))
        minutes = min(EXERCISE_WEEKLY_TARGET, 5 * math.ceil(start / 5))
        why = (f"Mulai dari {minutes} menit minggu ini, naik bertahap sampai 150 menit (WHO 2020)."
               if minutes < EXERCISE_WEEKLY_TARGET else "Target WHO 2020: 150 menit per minggu.")
    else:
        minutes = EXERCISE_WEEKLY_TARGET
        why = "Kamu sudah sekitar 150 menit per minggu; pertahankan (WHO 2020)."
    return {"minutes": minutes, "why": why}


def exercise_for_day(d: date, ctx: PlanContext, prefs: PlanPrefs) -> dict | None:
    if ctx.exercise_blocked:
        return {"minutes": 0, "activity": None, "time": None, "strength": False, "blocked": True,
                "why": "Ada penanda tekanan darah yang perlu perhatian. Bicarakan dengan tenaga kesehatan sebelum "
                       "memulai latihan baru; aktivitas ringan sehari-hari tetap boleh."}
    days = sorted(set(prefs.exercise_days)) or [0, 2, 4]
    if len(days) == 7:
        days = days[:6]  # minimal satu hari istirahat
    if d.weekday() not in days:
        return None
    week = weekly_exercise_target(ctx)
    per_day = 5 * math.ceil(week["minutes"] / len(days) / 5)
    idx = days.index(d.weekday())
    kinds = prefs.exercise_kinds or ("jalan cepat",)
    strength = idx < min(prefs.strength_days, len(days))
    return {"minutes": per_day, "activity": kinds[(d.toordinal() + idx) % len(kinds)], "time": prefs.exercise_time,
            "strength": strength, "blocked": False,
            "why": week["why"] + (" Ditambah penguatan otot hari ini (WHO 2020: >= 2 hari per minggu)." if strength else "")}


# ---------- makan ----------

def dish_candidate(dish: DishRecord, foods: dict[str, FoodRecord]) -> Candidate:
    comps, totals = [], {k: 0.0 for k in NUTRIENTS}
    for part in expand_dish(dish, foods):
        n = nutrition_for(part.food, part.grams)
        comps.append({"name": part.label, "food_id": part.food.id, "grams": round(part.grams, 1),
                      **{k: round(n[k], 1) for k in NUTRIENTS}})
        for k in NUTRIENTS:
            totals[k] += n[k]
    return Candidate(dish.id, "dish", dish.name, tuple(comps), {k: round(v, 1) for k, v in totals.items()})


def food_candidate(food: FoodRecord) -> Candidate:
    n = nutrition_for(food, None)
    comp = {"name": food.name, "food_id": food.id, "grams": round(n["portion_g"], 1), **{k: round(n[k], 1) for k in NUTRIENTS}}
    return Candidate(food.id, "food", food.name, (comp,), {k: round(n[k], 1) for k in NUTRIENTS})


def candidates_for(slot: str, dishes: list[DishRecord], foods: dict[str, FoodRecord]) -> list[Candidate]:
    if slot == "snack":
        return [food_candidate(foods[f]) for f in SNACK_FOOD_IDS if f in foods]
    return [dish_candidate(d, foods) for d in dishes if slot in d.meal_kinds]


def disliked(c: Candidate, dislikes: tuple[str, ...]) -> bool:
    words = [normalize(x) for x in dislikes if normalize(x)]
    haystack = [normalize(c.title), normalize(c.id.replace("_", " "))] + [
        normalize(x) for comp in c.components for x in (comp["name"], comp["food_id"].replace("_", " "))]
    return any(w in h for w in words for h in haystack)


def fits(c: Candidate, budget: dict) -> bool:
    return (all(c.totals[k] <= budget[k] for k in ("sugar_g", "sodium_mg", "fat_g"))
            and c.totals["kcal"] <= budget["kcal"] * KCAL_TOLERANCE)


def _overshoot(c: Candidate, budget: dict) -> float:
    return max((c.totals[k] / budget[k]) if budget[k] > 0 else c.totals[k] + 1 for k in NUTRIENTS)


def _rank(seed: str, cid: str) -> str:
    return hashlib.sha256(f"{seed}|{cid}".encode()).hexdigest()


def _why(c: Candidate, budget: dict, slot: str, over: bool) -> str:
    label = SLOT_LABELS[slot]
    if over:
        return (f"Tidak ada usulan yang sepenuhnya di bawah anggaran {label}; ini yang paling ringan "
                f"({_n(c.totals['kcal'])} kkal, gula {_n(c.totals['sugar_g'])} g, natrium {_n(c.totals['sodium_mg'])} mg).")
    tight = max(("sugar_g", "sodium_mg", "fat_g"), key=lambda k: c.totals[k] / budget[k] if budget[k] else 0)
    unit = {"sugar_g": ("gula", "g"), "sodium_mg": ("natrium", "mg"), "fat_g": ("lemak", "g")}[tight]
    return (f"{unit[0].capitalize()} {_n(c.totals[tight])} {unit[1]}, masih di bawah anggaran {label} "
            f"{_n(budget[tight])} {unit[1]}; {_n(c.totals['kcal'])} kkal.")


def pick_meal(slot: str, budget: dict, cands: list[Candidate], *, seed: str, avoid: set[str],
              dislikes: tuple[str, ...], offset: int = 0) -> dict | None:
    pool = [c for c in cands if not disliked(c, dislikes)]
    if not pool:
        return None
    fresh = [c for c in pool if c.id not in avoid]
    # Urutan: pas anggaran dan belum dimakan 3 hari terakhir; pas anggaran walau berulang; paling ringan.
    ok = sorted((c for c in fresh if fits(c, budget)), key=lambda c: _rank(seed, c.id)) or sorted(
        (c for c in pool if fits(c, budget)), key=lambda c: _rank(seed, c.id))
    over = not ok
    ordered = ok or sorted(fresh or pool, key=lambda c: (_overshoot(c, budget), c.id))
    choice = ordered[offset % len(ordered)]
    return {"id": choice.id, "kind": choice.kind, "title": choice.title, "components": list(choice.components),
            "totals": choice.totals, "budget": {k: round(v, 1) for k, v in budget.items()}, "over_budget": over,
            "alternatives": len(ordered), "why": _why(choice, budget, slot, over)}


@dataclass(frozen=True)
class Catalog:
    dishes: tuple[DishRecord, ...]
    foods: dict  # id -> FoodRecord


def _meal_slots(d: date, ctx: PlanContext, prefs: PlanPrefs, catalog: Catalog, recent: list[set[str]],
                offsets: dict[str, int], budgets: dict[str, dict]) -> dict[str, dict | None]:
    avoid = set().union(*recent[-REPEAT_WINDOW_DAYS:]) if recent else set()
    out = {}
    for slot in MEAL_SLOTS:
        cands = candidates_for(slot, list(catalog.dishes), catalog.foods)
        out[slot] = pick_meal(slot, budgets[slot], cands, seed=f"{ctx.user_key}:{d.isoformat()}:{slot}", avoid=avoid,
                              dislikes=prefs.dislikes, offset=offsets.get(slot, 0))
        if out[slot]:
            avoid = avoid | {out[slot]["id"]}  # tidak mengulang hidangan yang sama di hari yang sama
    return out


def day_plan(d: date, ctx: PlanContext, prefs: PlanPrefs, catalog: Catalog, *, recent: list[set[str]] | None = None,
             offsets: dict[str, int] | None = None, consumed: dict | None = None,
             done_slots: set[str] | None = None) -> dict:
    """Rencana satu hari. `consumed`/`done_slots` (hanya untuk hari ini): sisa anggaran dibagi ke waktu makan yang
    belum lewat, dan alasannya disebut."""
    daily = daily_budget(ctx, prefs.goal)
    done = done_slots or set()
    budgets = {s: slot_budget(daily, s) for s in MEAL_SLOTS}
    adapted_note = None
    if consumed:
        left_slots = [s for s in MEAL_SLOTS if s not in done]
        share = sum(MEAL_SPLIT[s] for s in left_slots) or 1
        remaining = {k: max(daily[k] - consumed.get(k, 0.0), 0.0) for k in NUTRIENTS}
        for s in left_slots:
            budgets[s] = {k: remaining[k] * MEAL_SPLIT[s] / share for k in NUTRIENTS}
        done_share = sum(MEAL_SPLIT[s] for s in done if s in MEAL_SPLIT)
        # sudah memakai lebih dari jatah waktu makan yang lewat -> sisa hari dibuat lebih ringan
        over = [k for k in ("sugar_g", "sodium_mg") if consumed.get(k, 0.0) > daily[k] * done_share]
        adapted_note = (f"Disesuaikan dengan yang sudah kamu makan hari ini: sisa gula {_n(remaining['sugar_g'])} g, "
                        f"natrium {_n(remaining['sodium_mg'])} mg, {_n(remaining['kcal'])} kkal."
                        + (" Bagian berikutnya dipilih lebih ringan." if over else ""))
    meals = _meal_slots(d, ctx, prefs, catalog, recent or [], offsets or {}, budgets)
    slots = []
    for s in MEAL_SLOTS:
        m = meals[s]
        slots.append({"slot": s, "label": SLOT_LABELS[s], "time": prefs.meal_times.get(s), "kind": "meal",
                      "done": s in done, **(m or {"title": None, "why": "Tidak ada usulan yang cocok dengan preferensimu."}),
                      "drink": DRINK_SUGGESTION})
    exercise = exercise_for_day(d, ctx, prefs)
    sleep = sleep_plan(ctx, prefs)
    return {
        "date": d.isoformat(),
        "energy": energy_target(ctx, prefs.goal),
        "budget": {k: round(v, 1) for k, v in daily.items()},
        "meals": slots,
        "exercise": exercise,
        "sleep": sleep,
        "adapted": adapted_note,
        "disclaimer": DISCLAIMER,
    }


def plan_range(start: date, days: int, ctx: PlanContext, prefs: PlanPrefs, catalog: Catalog,
               offsets_by_date: dict[str, dict[str, int]] | None = None) -> list[dict]:
    """Rencana beberapa hari berturut-turut tanpa mengulang hidangan yang sama dalam 3 hari. Tiga hari sebelum
    `start` ikut dihitung (tidak dikembalikan) supaya hari pertama juga tidak mengulang hari kemarin."""
    offsets_by_date = offsets_by_date or {}
    recent: list[set[str]] = []
    out = []
    for i in range(-REPEAT_WINDOW_DAYS, days):
        d = start + timedelta(days=i)
        plan = day_plan(d, ctx, prefs, catalog, recent=recent, offsets=offsets_by_date.get(d.isoformat()))
        recent.append({m["id"] for m in plan["meals"] if m.get("id") and m["slot"] != "snack"})
        if i >= 0:
            out.append(plan)
    return out


def recent_ids_before(d: date, ctx: PlanContext, prefs: PlanPrefs, catalog: Catalog,
                      offsets_by_date: dict | None = None) -> list[set[str]]:
    """Hidangan rencana 3 hari sebelum `d` (sama seperti plan_range), untuk rencana hari ini yang disesuaikan."""
    prev = plan_range(d - timedelta(days=REPEAT_WINDOW_DAYS), REPEAT_WINDOW_DAYS, ctx, prefs, catalog, offsets_by_date)
    return [{m["id"] for m in p["meals"] if m.get("id") and m["slot"] != "snack"} for p in prev]


def slot_for_time(moment: datetime) -> str:
    """Waktu makan untuk catatan pada jam tertentu (WIB): dipakai menandai bagian rencana yang sudah dimakan."""
    h = moment.hour
    if h < 10:
        return "breakfast"
    if h < 15:
        return "lunch"
    if h < 17:
        return "snack"
    return "dinner"
