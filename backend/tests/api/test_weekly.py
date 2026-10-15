from app.services.jobs import weekly_changes
from tests.api.test_summary import raka_headers

THIS = {"days_logged": 6, "sweet_drinks_per_day": 1.0, "sugar_g_per_day": 40.0, "sleep_hours_avg": 6.0,
        "active_minutes_per_day": 25.0}
PREV = {"days_logged": 5, "sweet_drinks_per_day": 2.0, "sugar_g_per_day": 55.0, "sleep_hours_avg": 5.0,
        "active_minutes_per_day": 10.0}


def test_perubahan_dinilai_membaik_untuk_gula_minuman_manis_dan_aktivitas():
    c = weekly_changes(THIS, PREV)
    assert c["sweet_drinks_per_day"] == {"delta": -1.0, "trend": "better"}
    assert c["sugar_g_per_day"] == {"delta": -15.0, "trend": "better"}
    assert c["active_minutes_per_day"] == {"delta": 15.0, "trend": "better"}


def test_tidur_hanya_menampilkan_selisih_tanpa_menilai():
    assert weekly_changes(THIS, PREV)["sleep_hours_avg"] == {"delta": 1.0, "trend": None}


def test_memburuk_dan_perubahan_kecil_dianggap_sama():
    worse = weekly_changes(PREV, THIS)
    assert worse["sweet_drinks_per_day"]["trend"] == "worse" and worse["active_minutes_per_day"]["trend"] == "worse"
    near = weekly_changes({**THIS, "sugar_g_per_day": 40.5}, THIS)
    assert near["sugar_g_per_day"]["trend"] == "same"


def test_tanpa_minggu_pembanding_tidak_ada_perubahan():
    assert weekly_changes(THIS, None) is None
    assert weekly_changes(THIS, {**PREV, "sleep_hours_avg": None})["sleep_hours_avg"] is None


async def test_rekap_mingguan_raka_punya_minggu_lalu_dan_pembanding(client, session_maker):
    h = await raka_headers(client, session_maker)
    r = await client.get("/summary/weekly", headers=h)
    assert r.status_code == 200
    week = r.json()["week"]
    assert week["metrics"]["days_logged"] >= 1 and week["start"] < week["end"]
    assert "Minggu" in week["text"]
    assert week["changes"] is not None and "sweet_drinks_per_day" in week["changes"]


async def test_pengguna_baru_belum_punya_rekap(client, auth_headers):
    assert (await client.get("/summary/weekly", headers=auth_headers)).json() == {"week": None}
    assert (await client.get("/summary/weekly")).status_code == 401
