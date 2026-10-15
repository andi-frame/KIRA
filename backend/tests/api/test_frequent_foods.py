from datetime import datetime, timedelta, timezone

from app.repos import logs as logs_repo
from tests.api.test_summary import raka_headers


async def add(session_maker, user_id, kind, name, days_ago, portion=100.0):
    async with session_maker() as s:
        await logs_repo.add_log(
            s, user_id, kind=kind, source="text", occurred_at=datetime.now(timezone.utc) - timedelta(days=days_ago),
            extracted={"items": [{"name": name}]}, raw_text=name,
            items=[logs_repo.ItemData(name=name, portion_g=portion, sugar_g=5)],
        )




async def test_makanan_sering_dicatat_diurutkan_dari_yang_paling_sering(client, auth_headers, session_maker):
    from sqlalchemy import text

    async with session_maker() as s:
        user_id = (await s.execute(text("select id from users limit 1"))).scalar_one()
    for d in (1, 2, 3):
        await add(session_maker, user_id, "meal", "nasi uduk", d, 200)
    for d in (1, 5):
        await add(session_maker, user_id, "drink", "teh manis", d, 250)
    await add(session_maker, user_id, "meal", "soto ayam", 1)  # hanya sekali: bukan "sering"
    foods = (await client.get("/logs/frequent", headers=auth_headers)).json()["foods"]
    assert [(f["name"], f["kind"], f["count"]) for f in foods] == [("nasi uduk", "meal", 3), ("teh manis", "drink", 2)]
    assert foods[0]["portion_g"] == 200 and foods[1]["portion_g"] == 250


async def test_catatan_lama_di_luar_jendela_dan_jenis_lain_tidak_ikut(client, auth_headers, session_maker):
    from sqlalchemy import text

    async with session_maker() as s:
        user_id = (await s.execute(text("select id from users limit 1"))).scalar_one()
    for d in (70, 80):
        await add(session_maker, user_id, "meal", "gado-gado", d)
    for d in (1, 2):
        await add(session_maker, user_id, "sleep", "tidur", d)
    assert (await client.get("/logs/frequent", headers=auth_headers)).json()["foods"] == []
    wide = (await client.get("/logs/frequent?days=90", headers=auth_headers)).json()["foods"]
    assert [f["name"] for f in wide] == ["gado-gado"]


async def test_batas_jumlah_dan_data_pengguna_lain_tidak_bocor(client, auth_headers, session_maker):
    await raka_headers(client, session_maker)
    assert (await client.get("/logs/frequent", headers=auth_headers)).json()["foods"] == []
    h = await raka_headers(client, session_maker)
    foods = (await client.get("/logs/frequent?limit=3", headers=h)).json()["foods"]
    assert 0 < len(foods) <= 3
    assert (await client.get("/logs/frequent?limit=0", headers=h)).status_code == 422
    assert (await client.get("/logs/frequent")).status_code == 401
