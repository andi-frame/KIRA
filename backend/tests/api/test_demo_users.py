"""Pengguna demo (seed/demo_users.py): masing-masing bisa masuk, datanya berbeda sesuai ceritanya, dan pembuatannya
idempoten serta deterministik."""
import pytest

from seed import demo_users
from seed.demo_users import BY_KEY, PERSONAS, PIN, create_persona, phone_of, reset_persona


@pytest.fixture
async def seeded(session_maker):
    ids = {}
    async with session_maker() as session:
        for p in PERSONAS:
            ids[p.key] = await create_persona(session, p)
    return ids


async def login(client, key: str) -> dict:
    r = await client.post("/auth/login", json={"identifier": key, "pin": PIN})
    assert r.status_code == 200, f"{key}: {r.text}"
    return {"Authorization": f"Bearer {r.json()['access_token']}"}


async def get(client, headers, path: str, **params) -> dict:
    r = await client.get(path, params=params, headers=headers)
    assert r.status_code == 200, f"{path}: {r.text}"
    return r.json()


async def test_semua_persona_bisa_masuk_dengan_nama_atau_nomor(client, seeded):
    for p in PERSONAS:
        await login(client, p.key)
        r = await client.post("/auth/login", json={"identifier": phone_of(p), "pin": PIN})
        assert r.status_code == 200, p.key


async def test_pembuatan_idempoten_dan_reset_menghapus_bersih(client, seeded, session_maker):
    async with session_maker() as s:
        again = await create_persona(s, BY_KEY["sari"])
    assert again == seeded["sari"]  # tidak dobel
    h = await login(client, "sari")
    before = len((await get(client, h, "/records"))["records"])
    async with session_maker() as s:
        await create_persona(s, BY_KEY["sari"])
    assert len((await get(client, h, "/records"))["records"]) == before

    async with session_maker() as s:
        await reset_persona(s, BY_KEY["sari"])
        new_id = await create_persona(s, BY_KEY["sari"])
    assert new_id != seeded["sari"]
    h2 = await login(client, "sari")
    assert len((await get(client, h2, "/records"))["records"]) == before  # isi sama setelah dibuat ulang: deterministik


async def test_data_deterministik_antar_pembuatan(client, session_maker, seeded):
    async def snapshot(key: str):
        h = await login(client, key)
        days = (await get(client, h, "/logs/history", days=30))["days"]
        return [(d["totals"]["kcal"], len(d["meals"]), len(d["drinks"]), d["sleep_hours"], d["activity_minutes"]) for d in days]

    first = await snapshot("budi")
    async with session_maker() as s:
        await reset_persona(s, BY_KEY["budi"])
        await create_persona(s, BY_KEY["budi"])
    assert await snapshot("budi") == first


async def test_sari_hipertensi_terkontrol_dengan_protokol_nadi_dan_rekam_medis(client, seeded):
    h = await login(client, "sari")
    profile = await get(client, h, "/profile")
    assert profile["mode"] == "management" and profile["on_bp_medication"] is True
    protocol = (await get(client, h, "/bp-protocol"))["protocol"]
    assert protocol["status"] == "completed" and protocol["result"]["range"] == "below_threshold"
    assert protocol["avg_pulse"] and 60 <= protocol["avg_pulse"] <= 100
    recs = (await get(client, h, "/records"))["records"]
    assert {r["kind"] for r in recs} >= {"diagnosis", "medication", "lab", "vaccination", "allergy"}
    assert any(r["source"] == "chat" for r in recs)
    chat = (await get(client, h, "/chat/history"))["messages"]
    assert [m["role"] for m in chat] == ["user", "assistant"]


async def test_budi_prediabetes_gula_puasa_naik_dan_minuman_manis_banyak(client, seeded):
    h = await login(client, "budi")
    trends = await get(client, h, "/insights/trends", days=30)
    fasting = trends["clinical"]["fasting_glucose"]
    assert [p["value"] for p in fasting["points"]] == [101, 104, 108, 112, 118] and fasting["trend"] == "naik"
    assert any(f["kind"] == "fasting_glucose" for f in trends["triage"])
    history = (await get(client, h, "/logs/history", days=14))["days"]
    assert sum(len(d["drinks"]) for d in history) >= 15
    risk = await get(client, h, "/projection")
    assert risk["category_high"] in {"high", "very_high", "moderate"}


async def test_dewi_sehat_aktif_detak_istirahat_rendah_dan_risiko_rendah(client, seeded):
    h = await login(client, "dewi")
    hr = (await get(client, h, "/insights/trends", days=30))["clinical"]["resting_heart_rate"]
    assert hr["latest"]["value"] < 60 and hr["latest"]["range"] == "below_range"
    risk = await get(client, h, "/projection")
    assert risk["category_high"] in {"low", "slightly_elevated"}
    days = (await get(client, h, "/logs/history", days=14))["days"]
    assert sum(d["activity_minutes"] or 0 for d in days) >= 150
    flag = next(f for f in (await get(client, h, "/insights/trends", days=30))["triage"] if f["kind"] == "resting_heart_rate")
    assert flag["level"] == "info"  # di bawah 60 pada orang aktif hanya info, bukan peringatan


async def test_joko_diabetes_tensi_tinggi_perlu_perhatian_dan_banyak_rekam_medis(client, seeded):
    h = await login(client, "joko")
    assert (await get(client, h, "/profile"))["mode"] == "management"
    triage = (await get(client, h, "/insights/trends", days=30))["triage"]
    attention = {f["kind"] for f in triage if f["level"] == "perhatian"}
    assert {"blood_pressure", "fasting_glucose"} <= attention
    assert len((await get(client, h, "/records"))["records"]) >= 8
    summary = await get(client, h, "/summary/doctor", days=30)
    assert summary["medical_records"] and "Rekam medis yang dicatat pasien sendiri" in summary["text"]


async def test_nia_hari_tidur_pendek_bergula_lebih_tinggi(client, seeded):
    h = await login(client, "nia")
    patterns = (await get(client, h, "/insights/patterns", days=30))["sleep"]
    assert patterns["needs_more_data"] is False and patterns["short_days"] >= 5
    sugar = next(c for c in patterns["comparisons"] if c["key"] == "sugar_g")
    assert sugar["diff"] > 5, "hari setelah tidur pendek harus tampak bergula lebih tinggi"


async def test_tara_baru_tiga_hari_dan_tanpa_hasil_cek(client, seeded):
    h = await login(client, "tara")
    days = (await get(client, h, "/logs/history", days=14))["days"]
    assert sum(1 for d in days if d["logged"]) == 3
    assert all(not v["points"] for v in (await get(client, h, "/insights/trends", days=30))["clinical"].values())
    assert (await get(client, h, "/records"))["records"] == []


async def test_persona_berbeda_menghasilkan_proyeksi_berbeda(client, seeded):
    scores = {}
    for key in ("dewi", "sari", "budi", "joko"):
        h = await login(client, key)
        p = await get(client, h, "/projection")
        scores[key] = (p["score_low"] + p["score_high"]) / 2
    assert scores["dewi"] < scores["sari"] < scores["joko"]
    assert scores["dewi"] < scores["budi"]


async def test_daftar_persona_lengkap_dan_nomor_unik():
    phones = [phone_of(p) for p in PERSONAS]
    assert len(set(phones)) == len(phones)
    assert {p.key for p in PERSONAS} == {"sari", "budi", "dewi", "joko", "nia", "tara"}
    assert demo_users.PIN == "123456"
