"""Mesin kebiasaan untuk Beranda: sinyal dari catatan harian pengguna sendiri, kondisi hari ini, dan langkah berikutnya.

Fungsi murni. Sinyal adalah PENANDA kebiasaan, bukan diagnosis: kalimatnya menyebut kebiasaan dan angka dari data
pengguna, tidak pernah menyebut penyakit pasti. Faktor seperti tidur dan natrium ditampilkan sebagai sinyal, tidak
ditambahkan ke skor FINDRISC (di luar definisinya).

Ambang (sumber lengkap di docs/sumber-angka-klinis.md):
- Gula 50 g, natrium 2.000 mg, lemak 67 g per hari: Permenkes 30/2013 (DAILY_LIMITS). Mode pengelolaan: gula 25 g
  (asumsi KIRA, DAILY_LIMITS_MANAGEMENT).
- Aktivitas 150 menit/minggu intensitas sedang: WHO 2020 (sama dengan core_calc/goals.py).
- Tidur 7 jam atau lebih: konsensus AASM/SRS (Watson dkk. 2015); tidur pendek < 6 jam: keputusan KIRA
  (core_calc/patterns.py).
- "Perhatian" bila batas terlewati pada >= 3 dari 7 hari atau rata-ratanya di atas batas; "pantau" bila 1-2 hari:
  keputusan KIRA.
- Cakupan data: < 3 hari tercatat dalam 7 hari -> data kurang, tidak menyimpulkan apa pun.
"""
from dataclasses import asdict, dataclass, field

from app.core_calc.goals import GOAL_KINDS, SLEEP_TARGET_HOURS
from app.core_calc.patterns import SHORT_SLEEP_HOURS, compare_by_sleep

WEEKLY_ACTIVE_TARGET = float(GOAL_KINDS["active_minutes_week"]["default"])  # WHO 2020
DAILY_ACTIVE_TARGET = 30.0  # 150 menit dibagi 5 hari (sama dengan risk.ACTIVE_MINUTES_PER_DAY)
MIN_LOGGED_DAYS = 3
OVER_DAYS_ATTENTION = 3
SHORT_NIGHTS_ATTENTION = 3
MIN_SLEEP_NIGHTS = 3
LEVEL_ORDER = {"perhatian": 0, "pantau": 1, "baik": 2, "info": 3}

SOURCES = {
    "sugar_g": "Permenkes 30/2013: batas gula 50 g per hari",
    "sugar_g_management": "Mode pengelolaan: batas gula 25 g per hari (asumsi KIRA; ikuti arahan dokter/ahli gizi)",
    "sodium_mg": "Permenkes 30/2013: batas natrium 2.000 mg per hari",
    "fat_g": "Permenkes 30/2013: batas lemak 67 g per hari",
    "activity": "WHO 2020: dewasa minimal 150 menit aktivitas intensitas sedang per minggu",
    "sleep": "AASM/SRS (Watson dkk. 2015): dewasa tidur 7 jam atau lebih; batas tidur pendek 6 jam keputusan KIRA",
    "pattern": "Perbandingan dari catatanmu sendiri (bukan sebab-akibat)",
    "trend": "Selisih rata-rata minggu ini dan minggu lalu dari catatanmu; selisih kecil dianggap sama",
}

_NUTRIENTS = {
    "sugar_g": ("Gula", "g", "bila terus berlanjut, asupan gula tinggi dikaitkan dengan naiknya risiko gula darah tinggi"),
    "sodium_mg": ("Natrium (garam)", "mg", "bila terus berlanjut, asupan garam tinggi dikaitkan dengan naiknya tekanan darah"),
    "fat_g": ("Lemak", "g", "bila terus berlanjut, asupan lemak tinggi dikaitkan dengan naiknya berat badan"),
}

# Selisih lebih kecil dari ini dianggap "sama" (derau harian). Arah baik: turun untuk gula dan minuman manis, naik untuk aktif.
TREND_RULES = {
    "sweet_drinks_per_day": (0.2, -1),
    "sugar_g_per_day": (2.0, -1),
    "active_minutes_per_day": (3.0, +1),
    "sleep_hours_avg": (None, 0),  # hanya selisih; KIRA tidak menilai jam tidur di sini
}


def weekly_changes(this: dict, prev: dict | None) -> dict | None:
    """Selisih tiap kebiasaan terhadap minggu sebelumnya, dengan arah (better/worse/same) bila bisa dinilai."""
    if prev is None:
        return None
    out: dict[str, dict | None] = {}
    for key, (noise, good_sign) in TREND_RULES.items():
        a, b = this.get(key), prev.get(key)
        if a is None or b is None:
            out[key] = None
            continue
        delta = round(a - b, 1)
        if noise is None:
            trend = None
        elif abs(delta) < noise:
            trend = "same"
        else:
            trend = "better" if delta * good_sign > 0 else "worse"
        out[key] = {"delta": delta, "trend": trend}
    return out


@dataclass(frozen=True)
class Signal:
    key: str
    level: str  # perhatian | pantau | baik | info
    title: str
    detail: str
    source: str
    evidence: dict = field(default_factory=dict)


def _n(v: float) -> str:
    return f"{v:,.0f}".replace(",", ".") if abs(v) >= 10 else f"{v:.1f}".replace(".", ",").replace(",0", "")


def week_metrics(days: list[dict]) -> dict | None:
    """Rata-rata per hari tercatat untuk perbandingan mingguan (bentuk sama dengan ringkasan mingguan)."""
    logged = [d for d in days if d.get("logged")]
    if not logged:
        return None
    n = len(logged)
    sleep = [d["sleep_hours"] for d in logged if d.get("sleep_hours") is not None]
    return {
        "days_logged": n,
        "sugar_g_per_day": round(sum(d.get("sugar_g") or 0 for d in logged) / n, 1),
        "sweet_drinks_per_day": round(sum(d.get("sweet_drinks") or 0 for d in logged) / n, 2),
        "active_minutes_per_day": round(sum(d.get("active_minutes") or 0 for d in logged) / n, 1),
        "sleep_hours_avg": round(sum(sleep) / len(sleep), 1) if sleep else None,
    }


def _nutrient_signal(key: str, week: list[dict], limit: float, mode: str) -> Signal | None:
    label, unit, link = _NUTRIENTS[key]
    values = [float(d[key]) for d in week if d.get("logged") and d.get(key) is not None]
    if not values:
        return None
    avg = sum(values) / len(values)
    over = sum(1 for v in values if v > limit)
    source = SOURCES["sugar_g_management"] if key == "sugar_g" and mode == "management" else SOURCES[key]
    evidence = {"days": len(values), "days_over": over, "avg": round(avg, 1), "limit": limit, "unit": unit}
    if over >= OVER_DAYS_ATTENTION or avg > limit:
        return Signal(key, "perhatian", f"{label} sering melewati batas",
                      f"{label} melewati batas {_n(limit)} {unit} pada {over} dari {len(values)} hari tercatat "
                      f"(rata-rata {_n(avg)} {unit}). Ini kebiasaan, bukan diagnosis: {link}.", source, evidence)
    if over:
        return Signal(key, "pantau", f"{label} sesekali melewati batas",
                      f"{label} melewati batas {_n(limit)} {unit} pada {over} dari {len(values)} hari tercatat.", source, evidence)
    return Signal(key, "baik", f"{label} masih sesuai batas",
                  f"{label} berada di bawah {_n(limit)} {unit} pada semua {len(values)} hari tercatat.", source, evidence)


def _activity_signal(week: list[dict]) -> Signal:
    recorded = [float(d["active_minutes"]) for d in week if d.get("active_minutes") is not None]
    if not recorded:
        return Signal("activity", "info", "Belum ada catatan aktivitas",
                      "Ceritakan jalan kaki atau olahraga di Ngobrol, atau sambungkan Health Connect, supaya menit "
                      "aktifmu ikut terhitung.", SOURCES["activity"], {"minutes": None, "target": WEEKLY_ACTIVE_TARGET})
    total = sum(recorded)
    evidence = {"minutes": round(total, 1), "target": WEEKLY_ACTIVE_TARGET}
    if total >= WEEKLY_ACTIVE_TARGET:
        return Signal("activity", "baik", "Aktivitas mingguan tercapai",
                      f"{_n(total)} menit aktif dalam 7 hari terakhir, sudah melewati {_n(WEEKLY_ACTIVE_TARGET)} menit.",
                      SOURCES["activity"], evidence)
    return Signal("activity", "pantau", "Aktivitas masih di bawah target mingguan",
                  f"{_n(total)} dari {_n(WEEKLY_ACTIVE_TARGET)} menit aktif dalam 7 hari terakhir; sisa "
                  f"{_n(WEEKLY_ACTIVE_TARGET - total)} menit. Jalan cepat 30 menit beberapa hari sudah cukup.",
                  SOURCES["activity"], evidence)


def _sleep_signal(week: list[dict]) -> Signal:
    nights = [float(d["sleep_hours"]) for d in week if d.get("sleep_hours") is not None]
    if len(nights) < MIN_SLEEP_NIGHTS:
        return Signal("sleep", "info", "Catatan tidur masih sedikit",
                      f"Baru {len(nights)} malam tercatat dalam 7 hari. Ceritakan jam tidurmu supaya polanya terlihat.",
                      SOURCES["sleep"], {"nights": len(nights)})
    avg = sum(nights) / len(nights)
    short = sum(1 for h in nights if h < SHORT_SLEEP_HOURS)
    evidence = {"nights": len(nights), "avg_hours": round(avg, 1), "short_nights": short,
                "target_hours": SLEEP_TARGET_HOURS}
    if short >= SHORT_NIGHTS_ATTENTION:
        return Signal("sleep", "perhatian", "Sering tidur kurang dari 6 jam",
                      f"{short} dari {len(nights)} malam tidur kurang dari {_n(SHORT_SLEEP_HOURS)} jam (rata-rata "
                      f"{_n(avg)} jam). Kurang tidur yang berlanjut dikaitkan dengan naiknya selera makan manis dan "
                      "tekanan darah.", SOURCES["sleep"], evidence)
    if avg < SLEEP_TARGET_HOURS:
        return Signal("sleep", "pantau", "Rata-rata tidur di bawah 7 jam",
                      f"Rata-rata {_n(avg)} jam dari {len(nights)} malam tercatat; anjuran dewasa 7 jam atau lebih.",
                      SOURCES["sleep"], evidence)
    return Signal("sleep", "baik", "Tidur cukup",
                  f"Rata-rata {_n(avg)} jam dari {len(nights)} malam tercatat.", SOURCES["sleep"], evidence)


def _pattern_signal(days: list[dict]) -> Signal | None:
    result = compare_by_sleep(days)
    sugar = next((c for c in result["comparisons"] if c.key == "sugar_g"), None)
    if sugar is None or abs(sugar.diff) < 1:
        return None
    direction = "lebih tinggi" if sugar.diff > 0 else "lebih rendah"
    return Signal("sleep_sugar_pattern", "info", "Pola tidur dan gula",
                  f"Di hari setelah tidur kurang dari {_n(SHORT_SLEEP_HOURS)} jam, gulamu rata-rata {_n(abs(sugar.diff))} g "
                  f"{direction} ({sugar.n_short} hari) dibanding hari lain ({sugar.n_other} hari). Ini pola dari catatanmu, "
                  "bukan sebab pasti.", SOURCES["pattern"],
                  {"short_avg": sugar.short_avg, "other_avg": sugar.other_avg, "n_short": sugar.n_short,
                   "n_other": sugar.n_other})


def _trend_signal(this: dict | None, prev: dict | None) -> Signal | None:
    changes = weekly_changes(this, prev) if this else None
    sugar = (changes or {}).get("sugar_g_per_day")
    if not sugar or sugar["trend"] in (None, "same"):
        return None
    better = sugar["trend"] == "better"
    return Signal("sugar_trend", "baik" if better else "pantau",
                  "Gula minggu ini turun" if better else "Gula minggu ini naik",
                  f"Rata-rata gula per hari {'turun' if better else 'naik'} {_n(abs(sugar['delta']))} g dibanding minggu lalu.",
                  SOURCES["trend"], {"delta": sugar["delta"]})


def triage_signals(flags: list[dict]) -> list[Signal]:
    """Penanda hasil cek dari core_calc/triage.py (ambangnya tidak diduplikasi di sini)."""
    titles = {"blood_pressure": "Tekanan darah", "fasting_glucose": "Gula darah puasa", "random_glucose": "Gula darah sewaktu",
              "hba1c": "HbA1c", "diabetes_risk": "Proyeksi risiko diabetes", "no_results": "Belum ada hasil pemeriksaan",
              "findrisc": "Skrining FINDRISC"}
    return [Signal(f"result_{f['kind']}", f["level"], titles.get(f["kind"], "Hasil pemeriksaan"), f["text"],
                   "Penanda hasil pemeriksaan (KMK 303/2026, PERKENI 2021, ESH 2021)", {"kind": f["kind"]})
            for f in flags]


def sort_signals(signals: list[Signal]) -> list[Signal]:
    return sorted(signals, key=lambda s: LEVEL_ORDER.get(s.level, 9))


def habit_report(days: list[dict], limits: dict[str, float], mode: str = "prevention",
                 triage_flags: list[dict] | None = None) -> dict:
    """days: deret harian terurut (lama -> baru), 14-28 hari, kunci: date, logged, kcal, sugar_g, sodium_mg, fat_g,
    sweet_drinks, active_minutes, sleep_hours. Hari terakhir = hari ini."""
    week, prev_week = days[-7:], days[-14:-7]
    logged = sum(1 for d in week if d.get("logged"))
    signals = triage_signals(triage_flags or [])
    if logged < MIN_LOGGED_DAYS:
        signals.append(Signal("data", "info", "Catatan minggu ini masih sedikit",
                              f"Baru {logged} dari 7 hari tercatat. Dengan minimal {MIN_LOGGED_DAYS} hari, KIRA bisa "
                              "membaca kebiasaanmu tanpa menebak.", "Aturan cakupan data KIRA", {"logged_days": logged}))
        return {"data_quality": "kurang", "logged_days": logged, "signals": [asdict(s) for s in sort_signals(signals)]}
    for key in ("sugar_g", "sodium_mg", "fat_g"):
        s = _nutrient_signal(key, week, limits[key], mode)
        if s:
            signals.append(s)
    signals += [_activity_signal(week), _sleep_signal(week)]
    for extra in (_pattern_signal(days), _trend_signal(week_metrics(week), week_metrics(prev_week))):
        if extra:
            signals.append(extra)
    return {"data_quality": "cukup", "logged_days": logged, "signals": [asdict(s) for s in sort_signals(signals)]}


# Jam (WIB) sejak kapan sebuah waktu makan wajar sudah tercatat, untuk "langkah berikutnya".
MEAL_SLOTS = ((10, "sarapan"), (14, "makan siang"), (20, "makan malam"))
EXERCISE_UNTIL_HOUR = 21
SLEEP_FROM_HOUR = 20


def next_best_action(*, hour: int, meals_logged: int, active_minutes_today: float, has_attention_result: bool,
                     open_check: dict | None, bp_protocol_active: bool) -> dict:
    """Satu langkah paling berguna sekarang. Prioritas: penanda perhatian -> saran cek -> protokol tensi ->
    catat makan yang belum ada menurut jam -> sisa olahraga -> tidur. Deterministik."""
    if has_attention_result:
        return {"kind": "check", "text": "Ada hasil pemeriksaan yang perlu perhatian. Bicarakan dengan dokter atau "
                                         "Puskesmas; ringkasan untuk dokter bisa kamu bagikan dari Beranda."}
    if open_check:
        return {"kind": "check", "text": f"Saatnya cek: {open_check.get('reason') or 'ada pemeriksaan yang disarankan'}"}
    if bp_protocol_active:
        return {"kind": "measure_bp", "text": "Protokol tensi 7 hari sedang berjalan. Jangan lupa ukur pagi dan malam ini."}
    expected = sum(1 for slot_hour, _ in MEAL_SLOTS if hour >= slot_hour)
    if meals_logged < expected:
        missing = MEAL_SLOTS[meals_logged][1]
        return {"kind": "log_meal", "text": f"Belum ada catatan {missing}. Ceritakan di Ngobrol, satu kalimat cukup."}
    if active_minutes_today < DAILY_ACTIVE_TARGET and hour < EXERCISE_UNTIL_HOUR:
        left = DAILY_ACTIVE_TARGET - active_minutes_today
        return {"kind": "exercise", "text": f"Sisa {left:.0f} menit bergerak hari ini. Jalan cepat sore ini sudah cukup."}
    if hour >= SLEEP_FROM_HOUR:
        return {"kind": "sleep", "text": f"Targetmu tidur {SLEEP_TARGET_HOURS:.0f} jam. Mulai bersiap tidur supaya besok segar."}
    return {"kind": "log_meal", "text": "Catatan hari ini sudah lengkap sejauh ini. Ceritakan makan berikutnya di Ngobrol."}
