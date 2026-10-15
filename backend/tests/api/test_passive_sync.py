from datetime import datetime, timedelta

from sqlalchemy import text

from app.timeutil import WIB, utcnow
from tests.api.helpers import complete_profile


def _day(days_ago: int) -> datetime:
    return (utcnow().astimezone(WIB) - timedelta(days=days_ago)).replace(hour=7, minute=0, second=0, microsecond=0)


def steps(days_ago: int, minutes: int, count: int, hour_offset: int = 0) -> dict:
    start = _day(days_ago) + timedelta(hours=hour_offset)
    return {"start": start.isoformat(), "end": (start + timedelta(minutes=minutes)).isoformat(), "count": count}


def sleep(days_ago: int, hours: float) -> dict:
    end = _day(days_ago)
    return {"start": (end - timedelta(hours=hours)).isoformat(), "end": end.isoformat()}


async def rows(engine, kind=None):
    q = "select kind, source, extracted from logs where source = 'health_connect'" + (f" and kind = '{kind}'" if kind else "")
    async with engine.connect() as conn:
        return (await conn.execute(text(q + " order by occurred_at"))).all()


async def test_langkah_dan_tidur_menjadi_log_dengan_sumber_health_connect(client, auth_headers, engine):
    body = {"steps": [steps(1, 40, 4400), steps(2, 30, 1200)], "sleep": [sleep(1, 6.5)]}
    r = await client.post("/sync/passive", json=body, headers=auth_headers)
    assert r.status_code == 200, r.text
    assert r.json() == {"activity_days": 2, "sleep_nights": 1}
    act = await rows(engine, "activity")
    assert sorted(x[2]["minutes"] for x in act) == [0, 40]
    assert act[0][2]["steps"] in (1200, 4400)
    slp = await rows(engine, "sleep")
    assert slp[0][2]["hours"] == 6.5 and slp[0][2]["wake_time"] == "07:00" and slp[0][2]["bed_time"] == "00:30"


async def test_sinkron_ulang_tidak_menggandakan_catatan(client, auth_headers, engine):
    body = {"steps": [steps(1, 40, 4400)], "sleep": [sleep(1, 7)]}
    await client.post("/sync/passive", json=body, headers=auth_headers)
    await client.post("/sync/passive", json=body, headers=auth_headers)
    assert len(await rows(engine)) == 2


async def test_sinkron_ulang_dengan_data_lebih_baru_menggantikan_yang_lama(client, auth_headers, engine):
    await client.post("/sync/passive", json={"steps": [steps(1, 40, 4400)]}, headers=auth_headers)
    await client.post("/sync/passive", json={"steps": [steps(1, 40, 4400), steps(1, 20, 2200, hour_offset=3)]},
                      headers=auth_headers)
    act = await rows(engine, "activity")
    assert len(act) == 1 and act[0][2]["minutes"] == 60 and act[0][2]["steps"] == 6600


async def test_data_terlalu_lama_masa_depan_dan_tidur_tidak_wajar_diabaikan(client, auth_headers, engine):
    body = {
        "steps": [steps(40, 30, 3300), steps(-3, 30, 3300)],
        "sleep": [sleep(1, 0.4), sleep(2, 20), sleep(50, 7)],
    }
    r = await client.post("/sync/passive", json=body, headers=auth_headers)
    assert r.status_code == 200 and r.json() == {"activity_days": 0, "sleep_nights": 0}
    assert await rows(engine) == []


async def test_butuh_login(client):
    assert (await client.post("/sync/passive", json={"steps": [], "sleep": []})).status_code in (401, 403)


async def test_batas_ukuran_payload(client, auth_headers):
    big = {"steps": [steps(1, 1, 120)] * 20001}
    assert (await client.post("/sync/passive", json=big, headers=auth_headers)).status_code == 422


async def test_langkah_aktif_beberapa_hari_menurunkan_skor_risiko(client, auth_headers):
    await complete_profile(client, auth_headers, usual_active_30min=False)
    before = (await client.get("/projection", headers=auth_headers)).json()
    body = {"steps": [steps(d, 45, 5000) for d in (1, 2, 3, 4)]}
    await client.post("/sync/passive", json=body, headers=auth_headers)
    after = (await client.get("/projection", headers=auth_headers)).json()
    assert after["score_high"] < before["score_high"]


async def test_data_pengguna_lain_tidak_tersentuh(client, auth_headers, engine):
    await client.post("/sync/passive", json={"steps": [steps(1, 40, 4400)]}, headers=auth_headers)
    other = await client.post("/auth/register", json={"phone": "081200000077", "pin": "654321"})
    other_h = {"Authorization": f"Bearer {other.json()['access_token']}"}
    await client.post("/sync/passive", json={"steps": [steps(1, 10, 1200)]}, headers=other_h)
    assert len(await rows(engine, "activity")) == 2


async def test_sinkron_sebagian_hanya_menggantikan_hari_yang_dikirim(client, auth_headers, engine):
    await client.post("/sync/passive", json={"steps": [steps(1, 40, 4400), steps(3, 30, 3300)]}, headers=auth_headers)
    await client.post("/sync/passive", json={"steps": [steps(2, 20, 2200)]}, headers=auth_headers)
    assert sorted(x[2]["steps"] for x in await rows(engine, "activity")) == [2200, 3300, 4400]
    await client.post("/sync/passive", json={"steps": [steps(2, 10, 1200)]}, headers=auth_headers)
    assert sorted(x[2]["steps"] for x in await rows(engine, "activity")) == [1200, 3300, 4400]


async def test_hapus_data_pasif_hanya_menghapus_milik_sendiri_dan_hanya_health_connect(client, auth_headers, engine):
    await client.post("/sync/passive", json={"steps": [steps(1, 40, 4400)], "sleep": [sleep(1, 7)]}, headers=auth_headers)
    async with engine.begin() as conn:  # catatan manual milik pengguna yang sama
        await conn.execute(text(
            "insert into logs (id, user_id, occurred_at, kind, source, extracted) "
            "select gen_random_uuid(), id, now(), 'activity', 'text', '{\"minutes\": 10}' from users limit 1"
        ))
    other = await client.post("/auth/register", json={"phone": "081200000066", "pin": "654321"})
    other_h = {"Authorization": f"Bearer {other.json()['access_token']}"}
    await client.post("/sync/passive", json={"steps": [steps(1, 10, 1200)]}, headers=other_h)

    r = await client.delete("/sync/passive", headers=auth_headers)
    assert r.status_code == 200 and r.json() == {"deleted": 2}
    assert len(await rows(engine)) == 1  # milik pengguna lain tetap ada
    async with engine.connect() as conn:
        manual = (await conn.execute(text("select count(*) from logs where source = 'text'"))).scalar_one()
    assert manual == 1  # catatan manual tidak tersentuh


async def test_hapus_data_pasif_butuh_login(client):
    assert (await client.delete("/sync/passive")).status_code in (401, 403)
