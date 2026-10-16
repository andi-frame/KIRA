from datetime import date, timedelta

import pytest

from app.core_calc.constants import DAILY_LIMITS, DAILY_LIMITS_MANAGEMENT
from app.core_calc.habits import habit_report, next_best_action

TODAY = date(2026, 10, 16)


def day(offset: int, **values) -> dict:
    base = {"date": (TODAY - timedelta(days=offset)).isoformat(), "logged": True, "kcal": 1800, "sugar_g": 30,
            "sodium_mg": 1500, "fat_g": 50, "sweet_drinks": 0, "active_minutes": None, "sleep_hours": None}
    return {**base, **values}


def series(n: int = 14, **overrides_by_offset) -> list[dict]:
    """Hari terlama dulu; overrides_by_offset: {"d0": {...}} untuk hari ini, "d1" kemarin, dst."""
    return [day(o, **overrides_by_offset.get(f"d{o}", {})) for o in range(n - 1, -1, -1)]


def signal(report: dict, key: str) -> dict:
    return next(s for s in report["signals"] if s["key"] == key)


def report(days, limits=DAILY_LIMITS, mode="prevention", flags=None):
    return habit_report(days, limits, mode, flags)


def test_data_kurang_tidak_menyimpulkan_kebiasaan():
    days = [{**d, "logged": False} for d in series()]
    days[-1]["logged"] = days[-2]["logged"] = True
    r = report(days)
    assert r["data_quality"] == "kurang" and r["logged_days"] == 2
    assert [s["key"] for s in r["signals"]] == ["data"]


def test_data_kurang_tetap_menampilkan_penanda_hasil_cek():
    days = [{**d, "logged": False} for d in series()]
    flags = [{"level": "perhatian", "kind": "blood_pressure", "text": "Tekanan darah terakhir 150/95 mmHg ..."}]
    r = report(days, flags=flags)
    assert r["signals"][0]["key"] == "result_blood_pressure" and r["signals"][0]["level"] == "perhatian"


@pytest.mark.parametrize("over_days,level", [(0, "baik"), (1, "pantau"), (2, "pantau"), (3, "perhatian")])
def test_gula_menurut_jumlah_hari_melewati_batas(over_days, level):
    days = series(**{f"d{i}": {"sugar_g": 60} for i in range(over_days)})
    s = signal(report(days), "sugar_g")
    assert s["level"] == level and s["evidence"]["days_over"] == over_days
    assert "Permenkes 30/2013" in s["source"]


def test_tepat_di_batas_belum_melewati():
    days = series(**{f"d{i}": {"sugar_g": 50, "sodium_mg": 2000, "fat_g": 67} for i in range(7)})
    r = report(days)
    assert {signal(r, k)["level"] for k in ("sugar_g", "sodium_mg", "fat_g")} == {"baik"}


def test_rata_rata_di_atas_batas_tanpa_tiga_hari_tetap_perhatian():
    days = series(d0={"sugar_g": 300}, d1={"sugar_g": 80})
    assert signal(report(days), "sugar_g")["level"] == "perhatian"  # rata-rata 7 hari > 50


def test_mode_pengelolaan_memakai_batas_gula_25():
    days = series(**{f"d{i}": {"sugar_g": 30} for i in range(7)})
    assert signal(report(days), "sugar_g")["level"] == "baik"
    s = signal(report(days, DAILY_LIMITS_MANAGEMENT, "management"), "sugar_g")
    assert s["level"] == "perhatian" and "asumsi KIRA" in s["source"]


@pytest.mark.parametrize("minutes,level", [(None, "info"), (149, "pantau"), (150, "baik")])
def test_aktivitas_mingguan_who(minutes, level):
    days = series(d0={"active_minutes": minutes})
    s = signal(report(days), "activity")
    assert s["level"] == level and "WHO 2020" in s["source"]


@pytest.mark.parametrize("hours,level", [
    ([6.5, 7.5], "info"),  # baru 2 malam: belum menyimpulkan
    ([5, 5.5, 5.9, 8], "perhatian"),  # 3 malam < 6 jam
    ([6.5, 6.5, 6.8], "pantau"),  # rata-rata < 7
    ([7, 7.5, 8], "baik"),
])
def test_tidur_aasm(hours, level):
    days = series(**{f"d{i}": {"sleep_hours": h} for i, h in enumerate(hours)})
    s = signal(report(days), "sleep")
    assert s["level"] == level and "AASM" in s["source"]


def test_pola_tidur_pendek_dan_gula_dari_catatan_sendiri():
    short = {f"d{i}": {"sleep_hours": 5, "sugar_g": 70} for i in range(0, 6, 2)}
    other = {f"d{i}": {"sleep_hours": 8, "sugar_g": 30} for i in range(1, 7, 2)}
    s = signal(report(series(**short, **other)), "sleep_sugar_pattern")
    assert s["level"] == "info" and "lebih tinggi" in s["detail"] and "bukan sebab pasti" in s["detail"]


def test_tren_gula_mingguan_memakai_ambang_derau():
    days = series(**{f"d{i}": {"sugar_g": 60} for i in range(7, 14)}, **{f"d{i}": {"sugar_g": 40} for i in range(7)})
    s = signal(report(days), "sugar_trend")
    assert s["level"] == "baik" and s["evidence"]["delta"] == -20
    flat = series(**{f"d{i}": {"sugar_g": 31} for i in range(7)})  # selisih 1 g < derau 2 g
    assert all(x["key"] != "sugar_trend" for x in report(flat)["signals"])


def test_urutan_perhatian_dulu_dan_tanpa_kata_terlarang():
    days = series(**{f"d{i}": {"sugar_g": 90, "sleep_hours": 5} for i in range(7)})
    r = report(days)
    levels = [s["level"] for s in r["signals"]]
    order = {"perhatian": 0, "pantau": 1, "baik": 2, "info": 3}
    assert levels == sorted(levels, key=order.get)
    text = " ".join(s["title"] + " " + s["detail"] for s in r["signals"]).lower()
    for word in (" aman", "menderita", "kamu diabetes", "kamu hipertensi"):
        assert word not in text


def test_setiap_sinyal_membawa_bukti_dan_sumber():
    r = report(series(d0={"active_minutes": 40, "sleep_hours": 7}))
    assert all(s["source"] and isinstance(s["evidence"], dict) for s in r["signals"])


BASE = dict(hour=13, meals_logged=1, active_minutes_today=0, has_attention_result=False, open_check=None,
            bp_protocol_active=False)


@pytest.mark.parametrize("changes,kind", [
    ({"has_attention_result": True, "open_check": {"reason": "x"}}, "check"),
    ({"open_check": {"reason": "Rentang risikomu masih lebar"}}, "check"),
    ({"bp_protocol_active": True}, "measure_bp"),
    ({"hour": 15, "meals_logged": 1}, "log_meal"),  # makan siang belum tercatat
    ({"hour": 15, "meals_logged": 2, "active_minutes_today": 10}, "exercise"),
    ({"hour": 21, "meals_logged": 3, "active_minutes_today": 10}, "sleep"),
    ({"hour": 15, "meals_logged": 2, "active_minutes_today": 30}, "log_meal"),
])
def test_langkah_berikutnya_mengikuti_prioritas(changes, kind):
    assert next_best_action(**{**BASE, **changes})["kind"] == kind


def test_langkah_berikutnya_menyebut_waktu_makan_yang_belum_ada():
    action = next_best_action(**{**BASE, "hour": 21, "meals_logged": 1})
    assert action == {"kind": "log_meal", "text": "Belum ada catatan makan siang. Ceritakan di Ngobrol, satu kalimat cukup."}
