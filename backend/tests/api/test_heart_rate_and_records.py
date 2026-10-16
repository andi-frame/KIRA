"""Detak jantung istirahat (hasil cek, tensi + nadi, tren, penanda) dan rekam medis pribadi (formulir dan chat)."""
import pytest

from tests.api.helpers import install_models, reset_models


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    reset_models()


# ---------- detak jantung ----------

async def test_simpan_detak_jantung_istirahat_muncul_di_tren_dengan_rentang(client, auth_headers):
    for bpm in (72, 105):
        r = await client.post("/results", json={"kind": "resting_heart_rate", "value": {"bpm": bpm}}, headers=auth_headers)
        assert r.status_code == 200 and r.json()["saved"] is True, r.text
    trends = (await client.get("/insights/trends", params={"days": 30}, headers=auth_headers)).json()
    hr = trends["clinical"]["resting_heart_rate"]
    assert [p["value"] for p in hr["points"]] == [72, 105]
    assert [p["range"] for p in hr["points"]] == ["normal_range", "above_range"]
    assert hr["latest"]["value"] == 105 and hr["trend"] == "naik"
    assert {r["value"] for r in hr["references"]} == {60, 100}
    flag = next(f for f in trends["triage"] if f["kind"] == "resting_heart_rate")
    assert flag["level"] == "pantau" and "di atas 100" in flag["text"]
    assert "aman" not in flag["text"].lower()


async def test_detak_jantung_rendah_hanya_info_karena_wajar_bagi_yang_berolahraga(client, auth_headers):
    await client.post("/results", json={"kind": "resting_heart_rate", "value": {"bpm": 52}}, headers=auth_headers)
    flags = (await client.get("/insights/trends", params={"days": 30}, headers=auth_headers)).json()["triage"]
    flag = next(f for f in flags if f["kind"] == "resting_heart_rate")
    assert flag["level"] == "info"


@pytest.mark.parametrize("value", [{"bpm": 10}, {"bpm": 400}, {}])
async def test_detak_jantung_mustahil_ditolak(client, auth_headers, value):
    r = await client.post("/results", json={"kind": "resting_heart_rate", "value": value}, headers=auth_headers)
    assert r.status_code == 422


async def test_tensi_boleh_disertai_nadi_dan_nadi_mustahil_ditolak(client, auth_headers):
    ok = await client.post("/results", json={"kind": "blood_pressure", "value": {"sys": 128, "dia": 82, "pulse": 74}}, headers=auth_headers)
    assert ok.status_code == 200
    bad = await client.post("/results", json={"kind": "blood_pressure", "value": {"sys": 128, "dia": 82, "pulse": 900}}, headers=auth_headers)
    assert bad.status_code == 422


async def test_protokol_tensi_menyimpan_nadi_per_bacaan_dan_rata_ratanya(client, auth_headers):
    await client.post("/bp-protocol", headers=auth_headers)
    for pulse in (70, 80):
        r = await client.post("/bp-protocol/readings", json={"sys": 124, "dia": 80, "session": "morning", "pulse": pulse},
                              headers=auth_headers)
        assert r.status_code == 200, r.text
    status = (await client.get("/bp-protocol", headers=auth_headers)).json()["protocol"]
    assert status["avg_pulse"] == 75 and status["pulse_readings"] == 2


async def test_chat_mencatat_detak_jantung_istirahat(client, auth_headers):
    install_models(extract={"items": [], "drinks": [], "activity": [], "intent": "result_input",
                            "clinical_result": {"kind": "resting_heart_rate", "value": {"bpm": 68}}})
    r = await client.post("/chat/message", json={"text": "detak jantungku pagi ini 68"}, headers=auth_headers)
    assert r.status_code == 200
    hr = (await client.get("/insights/trends", params={"days": 7}, headers=auth_headers)).json()["clinical"]["resting_heart_rate"]
    assert hr["latest"]["value"] == 68


async def test_ringkasan_dokter_memuat_detak_jantung(client, auth_headers):
    await client.post("/results", json={"kind": "resting_heart_rate", "value": {"bpm": 70}}, headers=auth_headers)
    r = await client.get("/summary/doctor", params={"days": 30}, headers=auth_headers)
    assert r.status_code == 200
    assert "Detak jantung istirahat" in r.text


# ---------- rekam medis ----------

RECORD = {"kind": "lab", "title": "Panel lipid", "recorded_on": "2026-09-01", "provider": "Lab Prodia",
          "details": "Puasa 10 jam", "values": [{"name": "Kolesterol total", "value": "210", "unit": "mg/dL"}]}


async def test_rekam_medis_tambah_lihat_ubah_hapus(client, auth_headers):
    created = await client.post("/records", json=RECORD, headers=auth_headers)
    assert created.status_code == 201, created.text
    rec = created.json()
    assert rec["kind_label"] == "Hasil laboratorium" and rec["values"][0]["value"] == "210"
    await client.post("/records", json={"kind": "allergy", "title": "Alergi udang"}, headers=auth_headers)

    listed = (await client.get("/records", headers=auth_headers)).json()["records"]
    assert [r["title"] for r in listed] == ["Alergi udang", "Panel lipid"]  # hari ini dulu, lalu yang lebih lama
    only = (await client.get("/records", params={"kind": "lab"}, headers=auth_headers)).json()["records"]
    assert [r["title"] for r in only] == ["Panel lipid"]

    changed = await client.patch(f"/records/{rec['id']}", json={"title": "Panel lipid lengkap", "details": None}, headers=auth_headers)
    assert changed.status_code == 200 and changed.json()["title"] == "Panel lipid lengkap" and changed.json()["details"] is None
    assert (await client.delete(f"/records/{rec['id']}", headers=auth_headers)).status_code == 204
    assert (await client.delete(f"/records/{rec['id']}", headers=auth_headers)).status_code == 404


async def test_rekam_medis_tidak_bisa_dilihat_atau_diubah_orang_lain(client, auth_headers):
    rec = (await client.post("/records", json=RECORD, headers=auth_headers)).json()
    other = await client.post("/auth/register", json={"phone": "081200000002", "username": "orang_lain", "consent": True, "pin": "123456"})
    headers = {"Authorization": f"Bearer {other.json()['access_token']}"}
    assert (await client.get("/records", headers=headers)).json()["records"] == []
    assert (await client.patch(f"/records/{rec['id']}", json={"title": "x"}, headers=headers)).status_code == 404
    assert (await client.delete(f"/records/{rec['id']}", headers=headers)).status_code == 404


async def test_tanggal_rekam_medis_di_masa_depan_dipotong_ke_hari_ini(client, auth_headers):
    rec = (await client.post("/records", json={**RECORD, "recorded_on": "2999-01-01"}, headers=auth_headers)).json()
    from app.timeutil import local_date, utcnow
    assert rec["recorded_on"] == local_date(utcnow()).isoformat()


async def test_rekam_medis_dari_cerita_di_chat_disimpan_dan_diklasifikasikan(client, auth_headers):
    chat, _ = install_models(extract={
        "items": [], "drinks": [], "activity": [], "clinical_result": None, "intent": "medical_record",
        "medical_record": {"kind": "medication", "title": "Metformin 500 mg", "details": "2 kali sehari sesudah makan",
                           "provider": "dr. Rina"}})
    r = await client.post("/chat/message", json={"text": "dokter kasih aku metformin 500 mg dua kali sehari"}, headers=auth_headers)
    assert r.status_code == 200
    recs = (await client.get("/records", headers=auth_headers)).json()["records"]
    assert len(recs) == 1 and recs[0]["kind"] == "medication" and recs[0]["source"] == "chat"
    seen = "\n".join(str(m.content) for m in chat.seen[-1])
    assert "Rekam medis TERSIMPAN" in seen and "jangan menyarankan obat" in seen
    # cerita riwayat medis bukan catatan makan/minum: tidak ada log baru
    day = (await client.get("/logs/history", params={"days": 1}, headers=auth_headers)).json()["days"][0]
    assert day["logged"] is False


async def test_rekam_medis_masuk_ekspor_akun(client, auth_headers):
    await client.post("/records", json=RECORD, headers=auth_headers)
    data = (await client.get("/account/export", headers=auth_headers)).json()
    assert [r["title"] for r in data["medical_records"]] == ["Panel lipid"]
