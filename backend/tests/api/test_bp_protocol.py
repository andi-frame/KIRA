from datetime import datetime, timedelta

import pytest
from sqlalchemy import text

from app.timeutil import WIB


def at(days_ago: int, hour: int, minute: int = 0) -> str:
    local = datetime.now(WIB).replace(hour=hour, minute=minute, second=0, microsecond=0) - timedelta(days=days_ago)
    return local.isoformat()


async def start(client, headers):
    r = await client.post("/bp-protocol", headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


async def backdate(engine, days: int = 6):
    """Putaran dimulai tengah malam (WIB) `days` hari lalu, sehingga bacaan hari itu pukul 07.00 selalu sesudah mulai."""
    midnight = datetime.now(WIB).replace(hour=0, minute=0, second=0, microsecond=0) - timedelta(days=days)
    async with engine.begin() as conn:
        await conn.execute(text("update bp_protocols set started_at = :t"), {"t": midnight})


async def reading(client, headers, sys, dia, session, when):
    return await client.post(
        "/bp-protocol/readings", json={"sys": sys, "dia": dia, "session": session, "measured_at": when}, headers=headers
    )


async def fill(client, headers, days_ago: list[int], sys=124, dia=80):
    """Dua bacaan berjarak 1 menit, pagi dan malam, untuk tiap hari."""
    for d in days_ago:
        for session, hour in (("morning", 7), ("evening", 20)):
            for minute in (0, 1):
                if d == 0 and hour > datetime.now(WIB).hour:
                    continue  # jangan mengisi waktu yang belum terjadi
                r = await reading(client, headers, sys, dia, session, at(d, hour, minute))
                assert r.status_code == 200, r.text


async def test_belum_ada_putaran_menampilkan_panduan_dengan_sumber(client, auth_headers):
    body = (await client.get("/bp-protocol", headers=auth_headers)).json()
    assert body["protocol"] is None
    g = body["guide"]
    assert (g["protocol_days"], g["min_days"], g["min_readings"]) == (7, 3, 12)
    assert g["home_threshold"] == {"sys": 135, "dia": 85} and "ESH 2021" in g["source"]


async def test_mulai_membuat_putaran_aktif_dengan_tujuh_hari_kosong(client, auth_headers):
    p = (await start(client, auth_headers))["protocol"]
    assert p["status"] == "active" and p["day_index"] == 1 and len(p["days"]) == 7
    assert all(d["morning"] == 0 and d["evening"] == 0 for d in p["days"])
    assert p["days"][0]["is_today"] is True and p["can_finish"] is False
    assert "3 hari lagi" in p["summary"]["missing"]


async def test_hanya_satu_putaran_aktif(client, auth_headers):
    await start(client, auth_headers)
    again = await client.post("/bp-protocol", headers=auth_headers)
    assert again.status_code == 409 and "berjalan" in again.json()["detail"]


async def test_catat_bacaan_masuk_ke_hitungan_pagi_dan_malam(client, auth_headers):
    await start(client, auth_headers)
    now = datetime.now(WIB)
    r = await reading(client, auth_headers, 128, 82, "morning", now.isoformat())
    body = r.json()
    assert r.status_code == 200 and body["saved"] is True and body["red_flag"] is None
    today = next(d for d in body["protocol"]["days"] if d["is_today"])
    assert (today["morning"], today["evening"]) == (1, 0)


async def test_bacaan_mustahil_atau_tidak_masuk_akal_ditolak_tanpa_menyimpan(client, auth_headers, engine):
    await start(client, auth_headers)
    now = datetime.now(WIB).isoformat()
    assert (await reading(client, auth_headers, 400, 80, "morning", now)).status_code == 422  # di luar batas skema
    assert (await reading(client, auth_headers, 120, 120, "morning", now)).status_code == 422  # diastolik >= sistolik
    bad_session = await client.post("/bp-protocol/readings", json={"sys": 120, "dia": 80, "session": "siang"}, headers=auth_headers)
    assert bad_session.status_code == 422
    async with engine.connect() as conn:
        assert (await conn.execute(text("select count(*) from bp_readings"))).scalar_one() == 0


async def test_bacaan_berbahaya_tidak_disimpan_dan_mengarahkan_ke_faskes(client, auth_headers, engine):
    await start(client, auth_headers)
    r = await reading(client, auth_headers, 190, 120, "morning", datetime.now(WIB).isoformat())
    assert r.status_code == 200 and r.json()["saved"] is False and r.json()["red_flag"]["kind"] == "blood_pressure"
    async with engine.connect() as conn:
        assert (await conn.execute(text("select count(*) from bp_readings"))).scalar_one() == 0


async def test_waktu_ukur_di_masa_depan_atau_sebelum_putaran_ditolak(client, auth_headers):
    await start(client, auth_headers)
    future = (datetime.now(WIB) + timedelta(hours=2)).isoformat()
    r = await reading(client, auth_headers, 120, 80, "morning", future)
    assert r.status_code == 422 and "masa depan" in r.json()["detail"]
    old = await reading(client, auth_headers, 120, 80, "morning", at(3, 7))
    assert old.status_code == 422 and "sebelum putaran" in old.json()["detail"]


async def test_maksimal_empat_bacaan_per_sesi_per_hari(client, auth_headers):
    await start(client, auth_headers)
    when = datetime.now(WIB)
    for i in range(4):
        assert (await reading(client, auth_headers, 120, 80, "morning", (when - timedelta(minutes=i)).isoformat())).status_code == 200
    over = await reading(client, auth_headers, 120, 80, "morning", (when - timedelta(minutes=9)).isoformat())
    assert over.status_code == 422 and "Cukup 2" in over.json()["detail"]
    assert (await reading(client, auth_headers, 120, 80, "evening", when.isoformat())).status_code == 200  # sesi lain bebas


async def test_catat_tanpa_putaran_aktif_ditolak(client, auth_headers):
    r = await reading(client, auth_headers, 120, 80, "morning", datetime.now(WIB).isoformat())
    assert r.status_code == 422 and "Mulai dulu" in r.json()["detail"]


async def test_selesai_butuh_tiga_hari_dan_dua_belas_bacaan_setelah_hari_pertama(client, auth_headers, engine):
    await start(client, auth_headers)
    await backdate(engine, 6)
    await fill(client, auth_headers, [6, 5])  # hari pertama (dibuang) + 1 hari terpakai
    status = (await client.get("/bp-protocol", headers=auth_headers)).json()["protocol"]
    assert status["can_finish"] is False
    r = await client.post("/bp-protocol/finish", headers=auth_headers)
    assert r.status_code == 422 and "Belum cukup" in r.json()["detail"]


async def test_selesai_menghitung_rata_rata_tanpa_hari_pertama_dan_menyimpan_satu_hasil(client, auth_headers, engine):
    await complete_profile_for_projection(client, auth_headers)
    await start(client, auth_headers)
    await backdate(engine, 6)
    await fill(client, auth_headers, [6], sys=170, dia=100)  # hari pertama: tinggi, harus dibuang
    await fill(client, auth_headers, [5, 4, 3], sys=124, dia=80)
    status = (await client.get("/bp-protocol", headers=auth_headers)).json()["protocol"]
    assert status["can_finish"] is True and status["summary"]["avg_sys"] == 124.0
    assert [d["discarded"] for d in status["days"][:3]] == [True, False, False]

    r = await client.post("/bp-protocol/finish", headers=auth_headers)
    assert r.status_code == 200, r.text
    body = r.json()
    assert body["red_flag"] is None and body["protocol"]["status"] == "completed"
    assert body["protocol"]["result"] == {
        "avg_sys": 124.0, "avg_dia": 80.0, "readings_used": 12, "completed_at": body["protocol"]["result"]["completed_at"],
        "range": "below_threshold",
    }
    assert "projection" in body
    async with engine.connect() as conn:
        rows = (await conn.execute(text("select kind, value from clinical_results"))).all()
        linked = (await conn.execute(text("select result_id from bp_protocols"))).scalar_one()
    assert len(rows) == 1 and rows[0][0] == "blood_pressure" and rows[0][1]["protocol"] and rows[0][1]["readings"] == 12
    assert linked is not None  # bacaan tunggal tidak ikut jadi hasil sendiri-sendiri


async def test_rata_rata_di_atas_ambang_rumah_menjadi_penanda_perhatian_di_tren(client, auth_headers, engine):
    await start(client, auth_headers)
    await backdate(engine, 6)
    await fill(client, auth_headers, [6])
    await fill(client, auth_headers, [5, 4, 3], sys=138, dia=86)
    assert (await client.post("/bp-protocol/finish", headers=auth_headers)).status_code == 200
    trends = (await client.get("/insights/trends", headers=auth_headers)).json()
    flag = next(f for f in trends["triage"] if f["kind"] == "blood_pressure")
    assert flag["level"] == "perhatian" and "Rata-rata tensi di rumah 138/86" in flag["text"] and "ESH 2021" in flag["text"]
    point = trends["clinical"]["blood_pressure"]["latest"]
    assert point["home_average"] is True and point["readings"] == 12


async def test_rata_rata_normal_tidak_menimbulkan_penanda_tensi(client, auth_headers, engine):
    await start(client, auth_headers)
    await backdate(engine, 6)
    await fill(client, auth_headers, [6])
    await fill(client, auth_headers, [5, 4, 3], sys=118, dia=76)
    await client.post("/bp-protocol/finish", headers=auth_headers)
    flags = (await client.get("/insights/trends", headers=auth_headers)).json()["triage"]
    assert not any(f["kind"] == "blood_pressure" for f in flags)


async def test_ringkasan_dokter_menamai_hasil_rata_rata_rumah(client, auth_headers, engine):
    await start(client, auth_headers)
    await backdate(engine, 6)
    await fill(client, auth_headers, [6])
    await fill(client, auth_headers, [5, 4, 3], sys=126, dia=82)
    await client.post("/bp-protocol/finish", headers=auth_headers)
    summary = (await client.get("/summary/doctor", headers=auth_headers)).json()
    row = summary["clinical_results"][0]
    assert row["label"] == "Tensi rata-rata di rumah (7 hari)" and row["display"] == "126/82 mmHg (12 bacaan)"
    assert (await client.get("/summary/doctor.pdf", headers=auth_headers)).content[:5] == b"%PDF-"


async def test_batal_menutup_putaran_dan_boleh_mulai_lagi(client, auth_headers):
    await start(client, auth_headers)
    assert (await client.delete("/bp-protocol", headers=auth_headers)).status_code == 200
    assert (await client.delete("/bp-protocol", headers=auth_headers)).status_code == 404
    assert (await client.get("/bp-protocol", headers=auth_headers)).json()["protocol"] is None
    assert (await client.post("/bp-protocol", headers=auth_headers)).status_code == 200


async def test_putaran_selesai_tetap_terlihat_hasilnya_sampai_putaran_baru(client, auth_headers, engine):
    await start(client, auth_headers)
    await backdate(engine, 6)
    await fill(client, auth_headers, [6])
    await fill(client, auth_headers, [5, 4, 3])
    await client.post("/bp-protocol/finish", headers=auth_headers)
    shown = (await client.get("/bp-protocol", headers=auth_headers)).json()["protocol"]
    assert shown["status"] == "completed" and shown["result"]["readings_used"] == 12
    assert (await client.post("/bp-protocol/finish", headers=auth_headers)).status_code == 422  # tidak ada yang berjalan


async def test_data_pengguna_lain_terpisah_dan_butuh_login(client, auth_headers):
    await start(client, auth_headers)
    other = await client.post("/auth/register", json={"phone": "081200000042", "username": "tetangga", "pin": "123456", "consent": True})
    oh = {"Authorization": f"Bearer {other.json()['access_token']}"}
    assert (await client.get("/bp-protocol", headers=oh)).json()["protocol"] is None
    assert (await client.get("/bp-protocol")).status_code == 401


async def complete_profile_for_projection(client, headers):
    from tests.api.helpers import complete_profile

    await complete_profile(client, headers)


@pytest.mark.parametrize("path", ["/bp-protocol/readings", "/bp-protocol/finish"])
async def test_endpoint_tulis_menolak_tanpa_token(client, path):
    assert (await client.post(path, json={"sys": 120, "dia": 80, "session": "morning"})).status_code == 401
