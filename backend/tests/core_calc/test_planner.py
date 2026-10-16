from datetime import date, timedelta

import pytest

from app.core_calc.constants import DAILY_LIMITS, DAILY_LIMITS_MANAGEMENT, MEAL_SPLIT
from app.core_calc.planner import (
    Catalog,
    PlanContext,
    PlanPrefs,
    day_plan,
    energy_target,
    exercise_for_day,
    plan_range,
    sleep_plan,
    slot_for_time,
    weekly_exercise_target,
)
from tests.core_calc.seed_data import seed_dishes, seed_foods

MONDAY = date(2026, 10, 12)
CAT = Catalog(seed_dishes(), seed_foods())
RAKA = PlanContext("raka", DAILY_LIMITS, age=28, sex="male", height_cm=170, weight_kg=78, recent_sleep_avg=5.5,
                   recent_weekly_active=40)


def week(ctx=RAKA, prefs=PlanPrefs(), start=MONDAY, days=7):
    return plan_range(start, days, ctx, prefs, CAT)


@pytest.mark.parametrize("age,sex,kcal", [(28, "male", 2650), (35, "male", 2550), (55, "male", 2150),
                                          (70, "male", 1800), (90, "male", 1600), (25, "female", 2250),
                                          (40, "female", 2150), (55, "female", 1800), (70, "female", 1550)])
def test_energi_dari_akg_2019(age, sex, kcal):
    e = energy_target(PlanContext("x", DAILY_LIMITS, age=age, sex=sex))
    assert e["kcal"] == kcal and "Permenkes 28/2019" in e["source"] and not e["adjusted"]


def test_defisit_hanya_bila_imt_25_dan_tujuan_turun_berat_dengan_batas_bawah():
    assert energy_target(RAKA, "turun_berat")["kcal"] == 2650 - 400  # IMT 27
    assert energy_target(RAKA, "jaga")["kcal"] == 2650
    lean = PlanContext("x", DAILY_LIMITS, age=28, sex="male", height_cm=180, weight_kg=65)  # IMT 20
    assert energy_target(lean, "turun_berat")["kcal"] == 2650
    elderly = PlanContext("x", DAILY_LIMITS, age=85, sex="female", height_cm=150, weight_kg=70)
    assert energy_target(elderly, "turun_berat")["kcal"] == 1200  # 1400 - 400 dibatasi lantai


def test_profil_belum_lengkap_memakai_bawaan_bertanda():
    e = energy_target(PlanContext("x", DAILY_LIMITS))
    assert e["kcal"] == 2150 and "Bawaan" in e["source"]


def test_tidur_kurang_menaikkan_target_ke_8_jam_dari_jam_bangun():
    s = sleep_plan(RAKA, PlanPrefs(wake_time="06:00"))
    assert s["hours"] == 8 and s["bedtime"] == "22:00" and "AASM" in s["source"]
    ok = PlanContext("x", DAILY_LIMITS, recent_sleep_avg=7.6)
    assert sleep_plan(ok, PlanPrefs(wake_time="05:30"))["hours"] == 7.5
    assert sleep_plan(ok, PlanPrefs(wake_time="05:30"))["bedtime"] == "22:00"


@pytest.mark.parametrize("recent,minutes", [(None, 30), (0, 30), (40, 50), (100, 120), (140, 150), (300, 150)])
def test_tanjakan_olahraga_sampai_150(recent, minutes):
    ctx = PlanContext("x", DAILY_LIMITS, recent_weekly_active=recent)
    assert weekly_exercise_target(ctx)["minutes"] == minutes


def test_olahraga_dibagi_ke_hari_pilihan_dan_selalu_ada_hari_istirahat():
    prefs = PlanPrefs(exercise_days=tuple(range(7)), strength_days=2)
    plans = [exercise_for_day(MONDAY + timedelta(days=i), RAKA, prefs) for i in range(7)]
    assert sum(p is None for p in plans) == 1
    assert sum(p["strength"] for p in plans if p) == 2
    assert sum(p["minutes"] for p in plans if p) >= weekly_exercise_target(RAKA)["minutes"]


def test_penanda_tensi_perhatian_tidak_memberi_latihan_baru():
    blocked = PlanContext("x", DAILY_LIMITS, exercise_blocked=True)
    p = exercise_for_day(MONDAY, blocked, PlanPrefs())
    assert p["blocked"] and p["minutes"] == 0 and "tenaga kesehatan" in p["why"]


def test_setiap_hari_tidak_melewati_batas_kecuali_ditandai():
    for plan in week():
        meals = [m for m in plan["meals"] if m.get("id")]
        assert len(meals) == 4
        for m in meals:
            if not m["over_budget"]:
                assert m["totals"]["sugar_g"] <= m["budget"]["sugar_g"]
                assert m["totals"]["sodium_mg"] <= m["budget"]["sodium_mg"]
        if not any(m["over_budget"] for m in meals):
            for k in ("sugar_g", "sodium_mg", "fat_g"):
                assert sum(m["totals"][k] for m in meals) <= DAILY_LIMITS[k]


def test_rencana_sama_untuk_masukan_sama_dan_berbeda_antar_pengguna():
    assert week() == week()
    other = PlanContext("orang_lain", DAILY_LIMITS, age=28, sex="male")
    assert [m["id"] for p in week() for m in p["meals"]] != [m["id"] for p in week(other) for m in p["meals"]]


def test_makan_siang_dan_malam_tidak_berulang_dalam_tiga_hari():
    plans = week(days=14)
    for slot in ("lunch", "dinner"):
        ids = [next(m["id"] for m in p["meals"] if m["slot"] == slot) for p in plans]
        for i in range(len(ids)):
            assert ids[i] not in ids[max(0, i - 2):i], (slot, i, ids)
    for p in plans:
        main = [m["id"] for m in p["meals"] if m["slot"] != "snack"]
        assert len(main) == len(set(main))  # tidak ada hidangan sama dua kali sehari


def test_preferensi_tidak_suka_dihormati():
    prefs = PlanPrefs(dislikes=("lele", "nasi telur", "telur"))
    for plan in week(prefs=prefs):
        for m in plan["meals"]:
            text = " ".join([m["title"] or ""] + [c["name"] for c in m.get("components", [])]).lower()
            assert "lele" not in text and "telur" not in text


def test_mode_pengelolaan_lebih_ketat():
    strict = PlanContext("raka", DAILY_LIMITS_MANAGEMENT, mode="management", age=28, sex="male")
    for plan in week(strict):
        assert plan["budget"]["sugar_g"] == 25
        for m in plan["meals"]:
            if m.get("id") and not m["over_budget"]:
                assert m["totals"]["sugar_g"] <= 25 * MEAL_SPLIT[m["slot"]] + 1e-9


def test_ganti_usulan_memilih_alternatif_lain_yang_tetap_pas():
    base = day_plan(MONDAY, RAKA, PlanPrefs(), CAT)
    swapped = day_plan(MONDAY, RAKA, PlanPrefs(), CAT, offsets={"lunch": 1})
    lunch = lambda p: next(m for m in p["meals"] if m["slot"] == "lunch")  # noqa: E731
    assert lunch(base)["id"] != lunch(swapped)["id"] and not lunch(swapped)["over_budget"]


def test_rencana_hari_ini_menyesuaikan_yang_sudah_dimakan():
    plan = day_plan(MONDAY, RAKA, PlanPrefs(), CAT, consumed={"kcal": 1500, "sugar_g": 45, "sodium_mg": 1900, "fat_g": 50},
                    done_slots={"breakfast", "lunch"})
    assert "sisa gula 5 g" in plan["adapted"] and "lebih ringan" in plan["adapted"]
    done = {m["slot"]: m["done"] for m in plan["meals"]}
    assert done == {"breakfast": True, "lunch": True, "snack": False, "dinner": False}
    dinner = next(m for m in plan["meals"] if m["slot"] == "dinner")
    assert dinner["budget"]["sodium_mg"] == pytest.approx(100 * 0.30 / 0.40)


def test_tanpa_klaim_penyakit_dan_selalu_ada_penafian():
    plan = day_plan(MONDAY, RAKA, PlanPrefs(), CAT)
    text = str(plan).lower()
    assert "bukan resep" in plan["disclaimer"] and " aman" not in text and "menderita" not in text


@pytest.mark.parametrize("hour,slot", [(7, "breakfast"), (12, "lunch"), (16, "snack"), (19, "dinner")])
def test_waktu_catatan_dipetakan_ke_waktu_makan(hour, slot):
    from datetime import datetime
    assert slot_for_time(datetime(2026, 10, 12, hour)) == slot
