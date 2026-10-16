"""Beberapa pengguna demo dengan data berbeda-beda, untuk memperagakan KIRA dari sudut yang berbeda. SEMUA DATA DUMMY.

Tiap persona punya cerita sendiri sehingga setiap layar punya sesuatu untuk ditunjukkan:

  raka   28 th  pekerja kantoran, tidur kurang, kopi manis, ayah diabetes (alur demo utama; data dari seed.raka)
  sari   54 th  hipertensi terkontrol (mode pengelolaan), diet rendah garam, protokol tensi 7 hari + nadi, rekam medis
  budi   46 th  prediabetes, gula puasa naik pelan-pelan, banyak minuman manis, kurang bergerak, saran cek terbuka
  dewi   24 th  sehat dan aktif, rajin olahraga, tidur cukup, detak jantung istirahat rendah, risiko rendah
  joko   67 th  diabetes dan tensi tinggi (mode pengelolaan), garam tinggi, banyak rekam medis, hasil perlu perhatian
  nia    31 th  pekerja shift: tidur tidak teratur, hari tidur pendek bergula lebih tinggi (memperagakan "pola tidur dan gula")
  tara   29 th  pengguna baru: profil lengkap tetapi baru 3 hari tercatat (memperagakan "data masih sedikit")

Semua masuk dengan PIN 123456 (dummy). Nama pengguna = nama persona (huruf kecil), nomor telepon dummy 0812000100NN.
Data deterministik: dijalankan dua kali menghasilkan isi yang sama.

Pakai (dari folder backend):
  uv run python -m seed.demo_users                  # buat semua yang belum ada
  uv run python -m seed.demo_users --reset          # hapus lalu buat ulang semua
  uv run python -m seed.demo_users --only sari,budi # hanya yang disebut
  uv run python -m seed.demo_users --list           # daftar persona dan cara masuk

Di Coolify/Docker:  docker exec -it <kontainer-backend> uv run --no-dev python -m seed.demo_users --reset
"""
import asyncio
import random
import sys
import uuid
from dataclasses import dataclass, field
from datetime import date, datetime, timedelta

from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.config import settings
from app.core_calc.findrisc import category
from app.models import (
    BpProtocol,
    BpReading,
    ClinicalResult,
    Diagnosis,
    Goal,
    MedicalRecord,
    Message,
    PlanPreference,
    RiskSnapshot,
    User,
)
from app.repos import foods as foods_repo
from app.repos import logs as logs_repo
from app.repos import profiles, users
from app.schemas.extraction import FoodItem
from app.schemas.profile import ProfileIn
from app.security import hash_pin
from app.services import account, risk
from app.services.meal_slot import infer_meal_slot
from app.services.nutrition_items import item_data, resolve_food_item
from app.timeutil import WIB, utcnow

PIN = "123456"
HISTORY_DAYS = 30


@dataclass
class Persona:
    key: str
    number: int
    name: str
    age: int
    sex: str
    height_cm: float
    weight_kg: float
    story: str
    profile: dict = field(default_factory=dict)
    diagnoses: list[tuple[str, int]] = field(default_factory=list)  # (kondisi, berapa hari lalu didiagnosis)
    days_logged: int = HISTORY_DAYS


PERSONAS = [
    Persona("sari", 2, "Sari", 54, "female", 158, 66, "hipertensi terkontrol, diet rendah garam",
            profile=dict(waist_cm=86, family_history_diabetes="second_degree", parent_hypertension=True, smoker=False,
                         on_bp_medication=True, history_high_glucose=False, usual_active_30min=True, usual_veg_fruit=True),
            diagnoses=[("hypertension", 420)]),
    Persona("budi", 3, "Budi", 46, "male", 168, 82, "prediabetes, gula puasa naik pelan-pelan",
            profile=dict(waist_cm=99, family_history_diabetes="first_degree", parent_hypertension=False, smoker=True,
                         on_bp_medication=False, history_high_glucose=True, usual_active_30min=False, usual_veg_fruit=False),
            diagnoses=[("prediabetes", 60)]),
    Persona("dewi", 4, "Dewi", 24, "female", 163, 53, "sehat dan aktif",
            profile=dict(waist_cm=68, family_history_diabetes="none", parent_hypertension=False, smoker=False,
                         on_bp_medication=False, history_high_glucose=False, usual_active_30min=True, usual_veg_fruit=True)),
    Persona("joko", 5, "Pak Joko", 67, "male", 165, 79, "diabetes dan tensi tinggi",
            profile=dict(waist_cm=102, family_history_diabetes="first_degree", parent_hypertension=True, smoker=False,
                         on_bp_medication=True, history_high_glucose=True, usual_active_30min=False, usual_veg_fruit=False),
            diagnoses=[("diabetes", 900), ("hypertension", 1500)]),
    Persona("nia", 6, "Nia", 31, "female", 160, 62, "pekerja shift, tidur tidak teratur",
            profile=dict(waist_cm=79, family_history_diabetes="second_degree", parent_hypertension=False, smoker=False,
                         on_bp_medication=False, history_high_glucose=False, usual_active_30min=False, usual_veg_fruit=False)),
    Persona("tara", 7, "Tara", 29, "female", 165, 58, "pengguna baru",
            profile=dict(waist_cm=72, family_history_diabetes="none", parent_hypertension=False, smoker=False,
                         on_bp_medication=False, history_high_glucose=False, usual_active_30min=True, usual_veg_fruit=True),
            days_logged=3),
]
BY_KEY = {p.key: p for p in PERSONAS}


def phone_of(p: Persona) -> str:
    return f"0812000100{p.number:02d}"


def _at(day_offset: int, hour: int, minute: int = 0) -> datetime:
    """Waktu WIB pada hari (hari ini - day_offset), dalam UTC. day_offset 0 = hari ini."""
    today: date = utcnow().astimezone(WIB).date()
    local = datetime.combine(today - timedelta(days=day_offset), datetime.min.time(), tzinfo=WIB)
    return (local + timedelta(hours=hour, minutes=minute)).astimezone(utcnow().tzinfo)


def _past(day_offset: int, hour: int, minute: int = 0) -> datetime:
    """Seperti _at tetapi tidak pernah di masa depan (untuk hari ini yang jamnya belum tiba)."""
    return min(_at(day_offset, hour, minute), utcnow() - timedelta(minutes=1))


# ---------- isi menu per persona (hidangan dari katalog, id dish) ----------

MENUS: dict[str, dict[str, list[str]]] = {
    "sari": {
        "breakfast": ["bubur_ayam_komplit", "nasi_pecel", "roti_telur", "lontong_sayur"],
        "lunch": ["nasi_pecel", "ikan_bakar_nasi", "nasi_warteg", "pecel_lele", "gado_gado_lontong"],
        "dinner": ["soto_ayam_nasi", "ikan_bakar_nasi", "nasi_gudeg", "ayam_bakar_komplit"],
    },
    "budi": {
        "breakfast": ["nasi_uduk_komplit", "nasi_kuning_komplit", "lontong_sayur"],
        "lunch": ["nasi_padang", "ayam_penyet", "mie_ayam_bakso", "nasi_goreng_telur", "bakso_komplit"],
        "dinner": ["nasi_goreng_telur", "ayam_geprek", "mie_instan_telur", "sate_ayam_lontong"],
    },
    "dewi": {
        "breakfast": ["roti_telur", "nasi_telur", "bubur_ayam_komplit"],
        "lunch": ["gado_gado_lontong", "nasi_pecel", "ikan_bakar_nasi", "ayam_bakar_komplit"],
        "dinner": ["ikan_bakar_nasi", "soto_ayam_nasi", "nasi_warteg"],
    },
    "joko": {
        "breakfast": ["nasi_uduk_komplit", "lontong_sayur", "bubur_ayam_komplit"],
        "lunch": ["nasi_padang", "nasi_rawon", "nasi_opor", "nasi_campur"],
        "dinner": ["nasi_padang", "mie_ayam_bakso", "bakso_komplit", "nasi_goreng_telur"],
    },
    "nia": {
        "breakfast": ["roti_telur", "mie_instan_telur"],
        "lunch": ["ayam_geprek", "nasi_ayam_krispi", "mie_ayam_bakso", "nasi_goreng_telur"],
        "dinner": ["nasi_telur", "mie_instan_telur", "nasi_ayam_goreng"],
    },
    "tara": {
        "breakfast": ["roti_telur", "nasi_telur"],
        "lunch": ["gado_gado_lontong", "nasi_ayam_goreng"],
        "dinner": ["ikan_bakar_nasi", "soto_ayam_nasi"],
    },
}
DRINKS = {
    "sari": [("teh_tawar", 1.0, 0.7), ("air_putih", 1.0, 0.9)],
    "budi": [("es_teh_manis", 2.0, 0.9), ("kopi_susu_gula_aren", 1.0, 0.6), ("teh_botol", 1.0, 0.4)],
    "dewi": [("air_putih", 1.0, 0.9), ("jus_jeruk", 1.0, 0.25)],
    "joko": [("es_teh_manis", 2.0, 0.8), ("kopi_sachet", 1.0, 0.7)],
    "nia": [("boba_milk_tea", 1.0, 0.5), ("kopi_susu_botol", 1.0, 0.7), ("es_teh_manis", 1.0, 0.4)],
    "tara": [("air_putih", 1.0, 0.9), ("teh_tawar", 1.0, 0.4)],
}
SLOT_HOURS = {"breakfast": (6, 30), "lunch": (12, 20), "dinner": (19, 0)}


async def _meal(session: AsyncSession, catalog, user_id: uuid.UUID, dish_id: str, day: int, slot: str, jitter: int) -> None:
    hour, minute = SLOT_HOURS[slot]
    when = _past(day, hour, minute + jitter)
    item = FoodItem(name=dish_id.replace("_", " "), dish_id=dish_id, meal_time=slot)
    res = resolve_food_item(item, catalog)
    chosen, sure = infer_meal_slot(slot, when, total_kcal=sum(i.kcal or 0 for i in res.items), main_dish=True)
    await logs_repo.add_log(
        session, user_id, kind="meal", source="text", occurred_at=when,
        extracted={"items": [item.model_dump()], "resolved": [res.trace]}, raw_text=item.name,
        items=res.items, commit=False, meal_slot=chosen, slot_confirmed=sure,
    )


async def _drink(session: AsyncSession, catalog, user_id: uuid.UUID, food_id: str, count: float, day: int, hour: int) -> None:
    food = catalog.by_id.get(food_id)
    await logs_repo.add_log(
        session, user_id, kind="drink", source="text", occurred_at=_past(day, hour),
        extracted={"name": food_id.replace("_", " "), "size": "gelas", "count": count}, raw_text=food_id.replace("_", " "),
        items=[item_data(food_id.replace("_", " "), food, None, multiplier=count)], commit=False,
    )


async def _sleep(session, user_id, day: int, bed: str, wake: str, hours: float) -> None:
    await logs_repo.add_log(
        session, user_id, kind="sleep", source="text", occurred_at=_past(day, 7),
        extracted={"bed_time": bed, "wake_time": wake, "hours": hours}, raw_text=f"tidur {bed} bangun {wake}", items=[], commit=False,
    )


async def _activity(session, user_id, day: int, hour: int, kind: str, minutes: int) -> None:
    await logs_repo.add_log(
        session, user_id, kind="activity", source="text", occurred_at=_past(day, hour),
        extracted={"kind": kind, "minutes": minutes}, raw_text=f"{kind} {minutes} menit", items=[], commit=False,
    )


async def _daily_logs(session: AsyncSession, catalog, user_id: uuid.UUID, p: Persona) -> None:
    rng = random.Random(f"kira-demo-{p.key}")  # deterministik per persona
    menu = MENUS[p.key]
    first_day = 1 if p.days_logged > 3 else 0
    for d in range(first_day, first_day + p.days_logged):
        for slot in ("breakfast", "lunch", "dinner"):
            skip = 0.35 if slot == "breakfast" and p.key in {"budi", "nia", "joko"} else 0.04
            if rng.random() < skip:
                continue
            await _meal(session, catalog, user_id, rng.choice(menu[slot]), d, slot, rng.randint(-10, 25))
        for food_id, count, prob in DRINKS[p.key]:
            if rng.random() < prob:
                await _drink(session, catalog, user_id, food_id, count if p.key != "dewi" else 1.0, d, rng.choice([9, 10, 14, 15]))
        await _sleep_and_activity(session, catalog, user_id, p, d, rng)


async def _sleep_and_activity(session, catalog, user_id, p: Persona, d: int, rng: random.Random) -> None:
    if p.key == "sari":
        await _sleep(session, user_id, d, "22:00", "05:30", 7.5)
        if d % 2 == 0:
            await _activity(session, user_id, d, 6, "jalan pagi", rng.choice([30, 40, 45]))
    elif p.key == "budi":
        await _sleep(session, user_id, d, rng.choice(["23:30", "00:30"]), "06:00", rng.choice([5.5, 6.0, 6.5]))
        if d % 6 == 0:
            await _activity(session, user_id, d, 17, "jalan santai", 20)
    elif p.key == "dewi":
        await _sleep(session, user_id, d, "22:30", "06:00", 7.5)
        if d % 7 != 0:
            await _activity(session, user_id, d, 6, rng.choice(["lari", "bersepeda", "yoga", "lari"]), rng.choice([30, 40, 50, 60]))
    elif p.key == "joko":
        await _sleep(session, user_id, d, "23:00", "03:30" if d % 3 == 0 else "05:00", 4.5 if d % 3 == 0 else 6.0)
        if d % 9 == 0:
            await _activity(session, user_id, d, 6, "jalan kaki", 15)
    elif p.key == "nia":
        # Hari setelah tidur pendek ditandai: minuman manis lebih banyak (dibuat di _short_sleep_extra).
        short = d % 2 == 0
        await _sleep(session, user_id, d, "03:00" if short else "00:00", "07:00" if short else "07:30", 4.0 if short else 7.5)
        if short:
            await _drink(session, catalog, user_id, "boba_milk_tea", 1.0, d, 16)
            await _drink(session, catalog, user_id, "minuman_soda", 1.0, d, 20)
    else:  # tara
        await _sleep(session, user_id, d, "22:30", "06:00", 7.5)
        if d == 1:
            await _activity(session, user_id, d, 17, "jalan cepat", 30)


# ---------- hasil cek, protokol tensi, rekam medis ----------

async def _result(session: AsyncSession, user_id: uuid.UUID, kind: str, value: dict, days_ago: int, source: str = "self") -> uuid.UUID:
    row = ClinicalResult(user_id=user_id, kind=kind, value=value, source=source, measured_at=_past(days_ago, 8, 15))
    session.add(row)
    await session.flush()
    return row.id


async def _bp_protocol(session: AsyncSession, user_id: uuid.UUID, days_ago_start: int, base: tuple[int, int], pulse: int, rng: random.Random) -> None:
    """Satu putaran 7 hari: 2 bacaan pagi dan 2 malam per hari, dengan nadi, lalu ditutup menjadi satu hasil rata-rata."""
    started = _past(days_ago_start, 7)
    protocol = BpProtocol(user_id=user_id, started_at=started, status="completed", completed_at=_past(days_ago_start - 7, 21))
    session.add(protocol)
    await session.flush()
    used: list[tuple[int, int]] = []
    for day in range(7):
        for session_name, hour in (("morning", 6), ("evening", 20)):
            for k in range(2):
                sys = base[0] + rng.randint(-6, 6)
                dia = base[1] + rng.randint(-4, 4)
                p = pulse + rng.randint(-5, 5)
                session.add(BpReading(protocol_id=protocol.id, user_id=user_id, session=session_name, sys=sys, dia=dia, pulse=p,
                                      measured_at=_past(days_ago_start - day, hour, 10 + k)))
                if day > 0:  # hari pertama dibuang dari rata-rata (ESH 2021)
                    used.append((sys, dia))
    avg_sys = sum(s for s, _ in used) / len(used)
    avg_dia = sum(d for _, d in used) / len(used)
    result_id = await _result(session, user_id, "blood_pressure", {
        "sys": round(avg_sys), "dia": round(avg_dia), "avg_sys": round(avg_sys, 1), "avg_dia": round(avg_dia, 1),
        "protocol": str(protocol.id), "readings": len(used), "pulse": pulse}, days_ago_start - 7)
    protocol.avg_sys, protocol.avg_dia, protocol.readings_used, protocol.result_id = avg_sys, avg_dia, len(used), result_id


def _record(user_id: uuid.UUID, kind: str, title: str, days_ago: int, provider: str | None = None, details: str | None = None,
            values: list[dict] | None = None, source: str = "manual") -> MedicalRecord:
    return MedicalRecord(user_id=user_id, kind=kind, title=title, recorded_on=_at(days_ago, 12).astimezone(WIB).date(),
                         provider=provider, details=details, values=values, source=source)


async def _clinical_and_records(session: AsyncSession, user_id: uuid.UUID, p: Persona) -> None:
    rng = random.Random(f"kira-demo-clinical-{p.key}")
    if p.key == "sari":
        await _bp_protocol(session, user_id, 25, (128, 82), 74, rng)
        for ago, sys, dia in ((60, 138, 88), (40, 132, 84), (12, 126, 80), (3, 124, 79)):
            await _result(session, user_id, "blood_pressure", {"sys": sys, "dia": dia, "pulse": 72}, ago)
        for ago, bpm in ((30, 76), (14, 74), (4, 72)):
            await _result(session, user_id, "resting_heart_rate", {"bpm": bpm}, ago)
        await _result(session, user_id, "fasting_glucose", {"mg_dl": 94}, 20, "lab")
        session.add_all([
            _record(user_id, "diagnosis", "Hipertensi", 420, "dr. Rina Puspita, Sp.PD", "Dikontrol dengan obat dan diet rendah garam."),
            _record(user_id, "medication", "Amlodipine 5 mg", 400, "dr. Rina Puspita, Sp.PD", "Satu kali sehari pagi hari (sesuai resep dokter)."),
            _record(user_id, "lab", "Panel lipid", 45, "Laboratorium Prodia", None, [
                {"name": "Kolesterol total", "value": "198", "unit": "mg/dL"}, {"name": "LDL", "value": "118", "unit": "mg/dL"},
                {"name": "HDL", "value": "52", "unit": "mg/dL"}, {"name": "Trigliserida", "value": "140", "unit": "mg/dL"}]),
            _record(user_id, "vaccination", "Vaksin influenza", 120, "Puskesmas Dago"),
            _record(user_id, "allergy", "Alergi udang", 3000, None, "Gatal dan bengkak bibir.", source="chat"),
        ])
    elif p.key == "budi":
        for ago, mg in ((150, 101), (110, 104), (75, 108), (35, 112), (6, 118)):
            await _result(session, user_id, "fasting_glucose", {"mg_dl": mg}, ago, "lab" if ago in (110, 35) else "self")
        await _result(session, user_id, "hba1c", {"percent": 5.9}, 30, "lab")
        await _result(session, user_id, "waist", {"cm": 99}, 20)
        for ago, sys, dia in ((50, 132, 86), (8, 136, 88)):
            await _result(session, user_id, "blood_pressure", {"sys": sys, "dia": dia}, ago)
        await _result(session, user_id, "resting_heart_rate", {"bpm": 82}, 9)
        session.add_all([
            _record(user_id, "diagnosis", "Prediabetes", 60, "dr. Hendra, Sp.PD", "Disarankan perubahan gaya hidup dan cek ulang 3 bulan."),
            _record(user_id, "lab", "HbA1c", 30, "Laboratorium Kimia Farma", None, [{"name": "HbA1c", "value": "5.9", "unit": "%"}]),
            _record(user_id, "visit", "Konsultasi ahli gizi", 40, "RS Santosa", "Diberi contoh porsi dan menu rendah gula."),
        ])
    elif p.key == "dewi":
        for ago, bpm in ((40, 56), (20, 58), (5, 57)):
            await _result(session, user_id, "resting_heart_rate", {"bpm": bpm}, ago)
        await _result(session, user_id, "blood_pressure", {"sys": 108, "dia": 68, "pulse": 58}, 25)
        await _result(session, user_id, "fasting_glucose", {"mg_dl": 84}, 70, "lab")
        session.add_all([
            _record(user_id, "vaccination", "Vaksin HPV dosis 2", 200, "Klinik Dago"),
            _record(user_id, "visit", "Pemeriksaan kesehatan tahunan", 90, "Klinik Pratama Sehat", "Semua hasil sesuai catatan dokter."),
        ])
    elif p.key == "joko":
        await _bp_protocol(session, user_id, 20, (148, 92), 94, rng)
        for ago, mg in ((200, 138), (120, 146), (60, 152), (14, 158)):
            await _result(session, user_id, "fasting_glucose", {"mg_dl": mg}, ago, "lab" if ago in (200, 60) else "self")
        for ago, pct in ((200, 7.1), (60, 7.4)):
            await _result(session, user_id, "hba1c", {"percent": pct}, ago, "lab")
        await _result(session, user_id, "random_glucose", {"mg_dl": 208}, 9)
        for ago, bpm in ((18, 98), (7, 96)):
            await _result(session, user_id, "resting_heart_rate", {"bpm": bpm}, ago)
        await _result(session, user_id, "waist", {"cm": 102}, 30)
        session.add_all([
            _record(user_id, "diagnosis", "Diabetes melitus tipe 2", 900, "dr. Bambang, Sp.PD", None),
            _record(user_id, "diagnosis", "Hipertensi", 1500, "dr. Bambang, Sp.PD", None),
            _record(user_id, "medication", "Metformin 500 mg", 880, "dr. Bambang, Sp.PD", "Dua kali sehari sesudah makan (sesuai resep dokter)."),
            _record(user_id, "medication", "Candesartan 8 mg", 700, "dr. Bambang, Sp.PD", "Satu kali sehari (sesuai resep dokter)."),
            _record(user_id, "lab", "HbA1c", 60, "Laboratorium Prodia", None, [{"name": "HbA1c", "value": "7.4", "unit": "%"}]),
            _record(user_id, "lab", "Fungsi ginjal", 60, "Laboratorium Prodia", None, [
                {"name": "Kreatinin", "value": "1.1", "unit": "mg/dL"}, {"name": "Ureum", "value": "34", "unit": "mg/dL"}]),
            _record(user_id, "procedure", "Operasi katarak mata kanan", 1100, "RS Mata Cicendo"),
            _record(user_id, "allergy", "Alergi penisilin", 5000, None, "Ruam kulit.", source="chat"),
            _record(user_id, "imaging", "Rontgen dada", 300, "RS Santosa", "Tidak ada keluhan baru."),
        ])
    elif p.key == "nia":
        await _result(session, user_id, "blood_pressure", {"sys": 118, "dia": 76}, 18)
        await _result(session, user_id, "resting_heart_rate", {"bpm": 78}, 10)
        session.add(_record(user_id, "visit", "Konsultasi tidur dengan dokter umum", 35, "Klinik Pratama Sehat", "Disarankan jadwal tidur yang lebih teratur."))
    # tara: sengaja tanpa hasil cek dan rekam medis


async def _risk_trail(session: AsyncSession, user_id: uuid.UUID, p: Persona) -> None:
    """Riwayat skor FINDRISC untuk grafik "dari waktu ke waktu"; skor terakhir dihitung dari data sungguhan di bawah."""
    trails = {
        "budi": [(120, 12, 16), (90, 13, 17), (60, 14, 18), (30, 15, 19)],
        "sari": [(100, 9, 13), (70, 8, 12), (40, 8, 11)],
        "joko": [(90, 17, 22), (60, 18, 22), (30, 18, 23)],
        "dewi": [(60, 2, 6), (30, 2, 5)],
        "nia": [(40, 6, 12), (20, 7, 12)],
    }
    for ago, low, high in trails.get(p.key, []):
        session.add(RiskSnapshot(user_id=user_id, model="findrisc", score_low=low, score_high=high, category_low=category(low),
                                 category_high=category(high), inputs={"demo": True}, computed_at=_past(ago, 9)))


async def _goals_and_prefs(session: AsyncSession, user_id: uuid.UUID, p: Persona) -> None:
    goals = {"sari": [("active_minutes_week", 150), ("sweet_drinks_week", 3)], "budi": [("sweet_drinks_week", 5), ("active_minutes_week", 120)],
             "dewi": [("active_minutes_week", 300)], "joko": [("sweet_drinks_week", 3), ("sleep_nights", 5)], "nia": [("sleep_nights", 4)]}
    for kind, target in goals.get(p.key, []):
        session.add(Goal(user_id=user_id, kind=kind, target=float(target)))
    if p.key in {"sari", "dewi"}:
        session.add(PlanPreference(user_id=user_id, exercise_time="06:00", exercise_days=[0, 1, 2, 3, 4, 5],
                                   exercise_kinds=["jalan cepat", "bersepeda"] if p.key == "sari" else ["lari", "yoga"], goal="jaga"))


async def _chat_today(session: AsyncSession, user_id: uuid.UUID, p: Persona) -> None:
    """Sedikit obrolan hari ini supaya riwayat obrolan tidak kosong saat didemokan (Sari dan Dewi)."""
    if p.key not in {"sari", "dewi"}:
        return
    today_meals = (await session.execute(
        text("select id from logs where user_id = :u and kind = 'meal' and occurred_at >= :s order by occurred_at limit 1"),
        {"u": user_id, "s": _at(0, 0)})).scalars().all()
    ids = [str(i) for i in today_meals]
    lines = [("user", "tadi sarapan bubur ayam, tidur semalam jam 10"),
             ("assistant", "Sudah kucatat. Sarapanmu masih sesuai targetmu hari ini, dan tidurmu cukup. Mau kubantu menyusun menu siang?")]
    base = _past(0, 7, 30)
    for i, (role, content) in enumerate(lines):
        session.add(Message(user_id=user_id, role=role, content=content, channel="app", created_at=base + timedelta(seconds=i * 20),
                            meta={"log_ids": ids if role == "assistant" else [], "red_flag": None}))


# ---------- pembuatan ----------

async def reset_persona(session: AsyncSession, p: Persona) -> None:
    await session.execute(text("delete from users where phone = :phone"), {"phone": phone_of(p)})
    await session.commit()


async def create_persona(session: AsyncSession, p: Persona) -> uuid.UUID:
    existing = await users.get_by_phone(session, phone_of(p))
    if existing is not None:
        return existing.id
    user = await users.create(session, phone_of(p), hash_pin(PIN), p.key)
    await account.record_consent(session, user.id)
    await profiles.update(session, user.id, ProfileIn(
        display_name=p.name, birth_date=date(utcnow().astimezone(WIB).year - p.age, 3, 14), sex=p.sex,
        height_cm=p.height_cm, weight_kg=p.weight_kg, **p.profile))
    for condition, ago in p.diagnoses:
        session.add(Diagnosis(user_id=user.id, condition=condition, diagnosed_at=_at(ago, 12).astimezone(WIB).date(), confirmed_by="dokter (data dummy)"))
    if p.diagnoses:
        row = await session.get(User, user.id)
        row.mode = "management"
    catalog = await foods_repo.catalog(session)
    await _daily_logs(session, catalog, user.id, p)
    await _clinical_and_records(session, user.id, p)
    await _risk_trail(session, user.id, p)
    await _goals_and_prefs(session, user.id, p)
    await session.flush()
    await _chat_today(session, user.id, p)
    # Nilai terkini dan saran cek dihitung dari data di atas, persis seperti saat pengguna sungguhan mencatat.
    state = await risk.compute_risk_state(session, user.id)
    await risk.save_snapshot_if_changed(session, user.id, state, commit=False)
    await risk.refresh_check_recommendation(session, user.id, state, commit=False)
    await session.commit()
    return user.id


async def _main(argv: list[str]) -> None:
    if "--list" in argv:
        print(f"{'nama pengguna':<14}{'telepon':<16}{'cerita'}")
        for p in PERSONAS:
            print(f"{p.key:<14}{phone_of(p):<16}{p.name}, {p.age} th: {p.story}")
        print(f"{'raka':<14}{'081234567890':<16}Raka, 28 th: alur demo utama (jalankan: uv run python -m seed.raka)")
        print(f"\nSemua PIN {PIN} (data dummy).")
        return
    wanted = None
    if "--only" in argv:
        wanted = {k.strip() for k in argv[argv.index("--only") + 1].split(",") if k.strip()}
        unknown = wanted - set(BY_KEY) - {"raka"}
        if unknown:
            raise SystemExit(f"Persona tidak dikenal: {', '.join(sorted(unknown))}. Lihat --list.")
    engine = create_async_engine(settings.database_url)
    try:
        async with async_sessionmaker(engine, expire_on_commit=False)() as session:
            if wanted is None or "raka" in wanted:
                from seed import raka

                if "--reset" in argv:
                    await raka.reset_raka(session)
                await raka.create_raka(session)
                print("raka   siap (alur demo utama)")
            for p in PERSONAS:
                if wanted is not None and p.key not in wanted:
                    continue
                if "--reset" in argv:
                    await reset_persona(session, p)
                uid = await create_persona(session, p)
                print(f"{p.key:<6} siap: {p.name}, {p.age} th, {p.story} (user {uid})")
        print(f"\nMasuk dengan nama pengguna (mis. sari) atau nomor telepon, PIN {PIN}. Data dummy.")
    finally:
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(_main(sys.argv[1:]))
