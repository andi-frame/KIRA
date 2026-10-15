from datetime import timedelta

from sqlalchemy import text

from app.services import check_followup
from app.timeutil import utcnow
from tests.api.helpers import complete_profile

OTHER = {"phone": "081200000066", "username": "pengguna_lain", "pin": "654321", "consent": True}


async def recommendation(client, headers):
    await complete_profile(client, headers)
    rec = (await client.get("/recommendations/check", headers=headers)).json()
    assert rec["test_kind"] == "fasting_glucose"
    return rec


async def age(engine, days: float):
    async with engine.begin() as conn:
        await conn.execute(text("update check_recommendations set created_at = :t"), {"t": utcnow() - timedelta(days=days)})


async def link_whatsapp(engine, jid="6281200000001@s.whatsapp.net"):
    async with engine.begin() as conn:
        uid = (await conn.execute(text("select id from users limit 1"))).scalar_one()
        await conn.execute(text("insert into wa_links (jid, user_id) values (:j, :u)"), {"j": jid, "u": uid})


async def outbox(engine):
    async with engine.connect() as conn:
        return (await conn.execute(text("select kind, text, ref from wa_outbox order by created_at"))).all()


async def test_rekomendasi_baru_belum_perlu_ditanyakan(client, auth_headers):
    rec = await recommendation(client, auth_headers)
    assert rec["age_days"] == 0 and rec["follow_up"] is False


async def test_setelah_tiga_hari_aplikasi_menandai_saatnya_bertanya(client, auth_headers, engine):
    await recommendation(client, auth_headers)
    await age(engine, 2.5)
    assert (await client.get("/recommendations/check", headers=auth_headers)).json()["follow_up"] is False
    await age(engine, 4)
    rec = (await client.get("/recommendations/check", headers=auth_headers)).json()
    assert rec["follow_up"] is True and rec["age_days"] == 4


async def test_nanti_menunda_pertanyaan_tiga_hari_tanpa_menutup_rekomendasi(client, auth_headers, engine):
    rec = await recommendation(client, auth_headers)
    await age(engine, 5)
    r = await client.post(f"/recommendations/{rec['id']}/respond", json={"action": "snooze"}, headers=auth_headers)
    assert r.status_code == 200 and r.json()["status"] == "open" and r.json()["result_needed"] is False
    after = (await client.get("/recommendations/check", headers=auth_headers)).json()
    assert after["id"] == rec["id"] and after["follow_up"] is False  # masih ada, hanya tidak ditanyakan
    async with engine.begin() as conn:
        await conn.execute(text("update check_recommendations set snoozed_until = :t"), {"t": utcnow() - timedelta(minutes=1)})
    assert (await client.get("/recommendations/check", headers=auth_headers)).json()["follow_up"] is True


async def test_sudah_dicek_menutup_dan_menawarkan_memasukkan_hasil_lalu_tidak_menagih_dulu(client, auth_headers, engine):
    rec = await recommendation(client, auth_headers)
    r = await client.post(f"/recommendations/{rec['id']}/respond", json={"action": "done"}, headers=auth_headers)
    assert r.json()["status"] == "done" and r.json()["result_needed"] is True and r.json()["test_kind"] == "fasting_glucose"
    # Pemicunya belum hilang (hasil belum dimasukkan), tetapi KIRA tidak langsung menagih lagi.
    assert (await client.get("/recommendations/check", headers=auth_headers)).json() is None
    # Dua minggu kemudian, bila hasil tetap tidak ada, KIRA boleh bertanya lagi.
    async with engine.begin() as conn:
        await conn.execute(text("update check_recommendations set snoozed_until = :t"), {"t": utcnow() - timedelta(minutes=1)})
    again = (await client.get("/recommendations/check", headers=auth_headers)).json()
    assert again is not None and again["id"] != rec["id"]


async def test_tidak_perlu_menahan_rekomendasi_sejenis_sebulan(client, auth_headers, engine):
    rec = await recommendation(client, auth_headers)
    out = (await client.post(f"/recommendations/{rec['id']}/respond", json={"action": "dismiss"}, headers=auth_headers)).json()
    assert out["status"] == "dismissed" and out["result_needed"] is False
    assert (await client.get("/recommendations/check", headers=auth_headers)).json() is None
    async with engine.connect() as conn:
        until = (await conn.execute(text("select snoozed_until from check_recommendations"))).scalar_one()
    assert timedelta(days=29) < until - utcnow() <= check_followup.HOLD_AFTER_DISMISS


async def test_memasukkan_hasil_tetap_menutup_rekomendasi_seperti_sebelumnya(client, auth_headers):
    await recommendation(client, auth_headers)
    await client.post("/results", json={"kind": "fasting_glucose", "value": {"mg_dl": 96}, "source": "lab"}, headers=auth_headers)
    rec = (await client.get("/recommendations/check", headers=auth_headers)).json()
    assert rec is None or rec["test_kind"] != "fasting_glucose"


async def test_jawaban_ditolak_untuk_rekomendasi_orang_lain_tidak_dikenal_atau_sudah_tertutup(client, auth_headers):
    rec = await recommendation(client, auth_headers)
    other = await client.post("/auth/register", json=OTHER)
    oh = {"Authorization": f"Bearer {other.json()['access_token']}"}
    assert (await client.post(f"/recommendations/{rec['id']}/respond", json={"action": "done"}, headers=oh)).status_code == 404
    missing = "00000000-0000-0000-0000-000000000000"
    assert (await client.post(f"/recommendations/{missing}/respond", json={"action": "done"}, headers=auth_headers)).status_code == 404
    assert (await client.post(f"/recommendations/{rec['id']}/respond", json={"action": "mungkin"}, headers=auth_headers)).status_code == 422
    assert (await client.post(f"/recommendations/{rec['id']}/respond", json={"action": "done"}, headers=auth_headers)).status_code == 200
    assert (await client.post(f"/recommendations/{rec['id']}/respond", json={"action": "done"}, headers=auth_headers)).status_code == 404
    assert (await client.post(f"/recommendations/{rec['id']}/respond", json={"action": "done"})).status_code == 401


async def test_whatsapp_bertanya_setelah_tiga_hari_dengan_contoh_pesan_hasil(client, auth_headers, engine, session_maker):
    await recommendation(client, auth_headers)
    await link_whatsapp(engine)
    await age(engine, 4)
    async with session_maker() as s:
        assert await check_followup.enqueue_followups(s) == 1
    kind, body, ref = (await outbox(engine))[0]
    assert kind == "followup" and "gula darah puasa" in body and "gula puasa 98" in body
    assert "tidak apa-apa" in body and ref.endswith(":0")


async def test_whatsapp_tidak_membanjiri_jarak_empat_hari_dan_maksimal_dua_kali(client, auth_headers, engine, session_maker):
    await recommendation(client, auth_headers)
    await link_whatsapp(engine)
    await age(engine, 4)
    async with session_maker() as s:
        assert await check_followup.enqueue_followups(s) == 1
        assert await check_followup.enqueue_followups(s) == 0  # langsung lagi: tidak
    async with engine.begin() as conn:
        await conn.execute(text("update check_recommendations set last_followup_at = :t"), {"t": utcnow() - timedelta(days=5)})
    async with session_maker() as s:
        assert await check_followup.enqueue_followups(s) == 1
    assert "sekali lagi" in (await outbox(engine))[1][1]
    async with engine.begin() as conn:
        await conn.execute(text("update check_recommendations set last_followup_at = :t"), {"t": utcnow() - timedelta(days=30)})
    async with session_maker() as s:
        assert await check_followup.enqueue_followups(s) == 0  # sudah dua kali
    assert len(await outbox(engine)) == 2


async def test_whatsapp_tidak_bertanya_bila_ditunda_baru_atau_tanpa_whatsapp(client, auth_headers, engine, session_maker):
    rec = await recommendation(client, auth_headers)
    async with session_maker() as s:
        assert await check_followup.enqueue_followups(s) == 0  # tanpa WhatsApp tertaut
    await link_whatsapp(engine)
    async with session_maker() as s:
        assert await check_followup.enqueue_followups(s) == 0  # masih baru
    await age(engine, 6)
    await client.post(f"/recommendations/{rec['id']}/respond", json={"action": "snooze"}, headers=auth_headers)
    async with session_maker() as s:
        assert await check_followup.enqueue_followups(s) == 0  # sedang ditunda
    assert await outbox(engine) == []


async def test_pengingat_tidak_dikirim_untuk_rekomendasi_yang_sudah_dijawab(client, auth_headers, engine, session_maker):
    rec = await recommendation(client, auth_headers)
    await link_whatsapp(engine)
    await age(engine, 6)
    await client.post(f"/recommendations/{rec['id']}/respond", json={"action": "dismiss"}, headers=auth_headers)
    async with session_maker() as s:
        assert await check_followup.enqueue_followups(s) == 0
