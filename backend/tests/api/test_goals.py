from datetime import datetime, timedelta, timezone

from sqlalchemy import text

from app.repos import logs as logs_repo
from app.timeutil import WIB, local_date, utcnow


async def uid_of(session_maker):
    async with session_maker() as s:
        return (await s.execute(text("select id from users limit 1"))).scalar_one()


def at(day: "datetime.date", hour: int = 12) -> datetime:
    return datetime(day.year, day.month, day.day, hour, tzinfo=WIB).astimezone(timezone.utc)


def monday_of(weeks_ago: int = 0):
    today = local_date(utcnow())
    return today - timedelta(days=today.weekday()) - timedelta(weeks=weeks_ago)


async def add_activity(session_maker, uid, day, minutes):
    async with session_maker() as s:
        await logs_repo.add_log(s, uid, kind="activity", source="text", occurred_at=at(day),
                                extracted={"minutes": minutes}, raw_text=None, items=[])


async def create(client, headers, kind, target=None):
    body = {"kind": kind, **({"target": target} if target is not None else {})}
    return await client.post("/goals", json=body, headers=headers)


async def test_tanpa_target_daftar_kosong_dengan_pilihan_jenis_dan_rentang(client, auth_headers):
    body = (await client.get("/goals", headers=auth_headers)).json()
    assert body["goals"] == []
    kinds = {k["kind"]: k for k in body["kinds"]}
    assert set(kinds) == {"active_minutes_week", "sweet_drinks_week", "sleep_nights", "logging_days"}
    assert kinds["active_minutes_week"]["default"] == 150 and kinds["active_minutes_week"]["direction"] == "min"
    assert kinds["sweet_drinks_week"]["direction"] == "max"
    w = body["week"]
    assert w["start"] <= local_date(utcnow()).isoformat() <= w["end"] and 0 <= w["days_left"] <= 6


async def test_buat_target_dengan_bawaan_lalu_kemajuan_dihitung_dari_catatan_minggu_ini(client, auth_headers, session_maker):
    r = await create(client, auth_headers, "active_minutes_week")
    assert r.status_code == 200
    goal = r.json()["goals"][0]
    assert goal["progress"]["target"] == 150 and goal["progress"]["current"] == 0 and goal["progress"]["status"] == "in_progress"

    uid = await uid_of(session_maker)
    await add_activity(session_maker, uid, monday_of(), 100)
    await add_activity(session_maker, uid, monday_of(), 60)
    after = (await client.get("/goals", headers=auth_headers)).json()["goals"][0]["progress"]
    assert after["current"] == 160 and after["met"] is True and after["status"] == "met" and after["fraction"] == 1.0


async def test_target_maksimum_minuman_manis_over_saat_melewati_batas(client, auth_headers, session_maker):
    await create(client, auth_headers, "sweet_drinks_week", 1)
    uid = await uid_of(session_maker)
    async with session_maker() as s:
        await logs_repo.add_log(
            s, uid, kind="drink", source="text", occurred_at=at(monday_of()), extracted={"name": "teh", "count": 2},
            raw_text=None, items=[logs_repo.ItemData(name="teh manis", sugar_g=40)],
        )
    p = (await client.get("/goals", headers=auth_headers)).json()["goals"][0]["progress"]
    assert p["current"] == 2 and p["status"] == "over" and p["met"] is False


async def test_riwayat_empat_minggu_minggu_tanpa_catatan_bukan_gagal(client, auth_headers, session_maker):
    await create(client, auth_headers, "active_minutes_week", 100)
    uid = await uid_of(session_maker)
    await add_activity(session_maker, uid, monday_of(2), 120)  # dua minggu lalu: tercapai
    await add_activity(session_maker, uid, monday_of(1), 30)  # minggu lalu: belum
    goal = (await client.get("/goals", headers=auth_headers)).json()["goals"][0]
    hist = {h["week_start"]: h for h in goal["history"]}
    assert hist[monday_of(2).isoformat()]["met"] is True
    assert hist[monday_of(1).isoformat()]["met"] is False and hist[monday_of(1).isoformat()]["current"] == 30
    assert hist[monday_of(4).isoformat()]["met"] is None  # tidak ada catatan: tidak dihitung
    assert goal["met_weeks"] == 1 and goal["weeks_with_data"] == 2


async def test_satu_target_per_jenis_dan_jenis_atau_angka_tidak_valid_ditolak(client, auth_headers):
    assert (await create(client, auth_headers, "logging_days", 5)).status_code == 200
    dup = await create(client, auth_headers, "logging_days", 6)
    assert dup.status_code == 409 and "sudah ada" in dup.json()["detail"]
    assert (await create(client, auth_headers, "langkah", 1000)).status_code == 422
    assert (await create(client, auth_headers, "sleep_nights", 9)).status_code == 422
    assert (await create(client, auth_headers, "active_minutes_week", 5)).status_code == 422


async def test_ubah_dan_hapus_target(client, auth_headers):
    gid = (await create(client, auth_headers, "sleep_nights", 5)).json()["goals"][0]["id"]
    changed = await client.patch(f"/goals/{gid}", json={"target": 6}, headers=auth_headers)
    assert changed.status_code == 200 and changed.json()["goals"][0]["progress"]["target"] == 6
    assert (await client.patch(f"/goals/{gid}", json={"target": 9}, headers=auth_headers)).status_code == 422
    assert (await client.delete(f"/goals/{gid}", headers=auth_headers)).status_code == 200
    assert (await client.get("/goals", headers=auth_headers)).json()["goals"] == []
    assert (await client.delete(f"/goals/{gid}", headers=auth_headers)).status_code == 404


async def test_target_milik_sendiri_dan_butuh_login(client, auth_headers):
    gid = (await create(client, auth_headers, "logging_days")).json()["goals"][0]["id"]
    other = await client.post("/auth/register", json={"phone": "081200000021", "username": "tetangga_dua", "pin": "123456", "consent": True})
    oh = {"Authorization": f"Bearer {other.json()['access_token']}"}
    assert (await client.get("/goals", headers=oh)).json()["goals"] == []
    assert (await client.patch(f"/goals/{gid}", json={"target": 3}, headers=oh)).status_code == 404
    assert (await client.delete(f"/goals/{gid}", headers=oh)).status_code == 404
    assert (await client.get("/goals")).status_code == 401
    assert (await client.post("/goals", json={"kind": "logging_days"})).status_code == 401
