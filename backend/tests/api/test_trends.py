from datetime import datetime, timedelta, timezone

from tests.api.test_summary import raka_headers


def ago(days: int) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()


async def post(client, headers, kind, value, days_ago, source="self"):
    r = await client.post(
        "/results", json={"kind": kind, "value": value, "source": source, "measured_at": ago(days_ago)}, headers=headers
    )
    assert r.status_code == 200, r.text


async def test_tren_tensi_berurutan_dengan_kategori_per_titik_dan_acuan_ambang(client, auth_headers):
    await post(client, auth_headers, "blood_pressure", {"sys": 145, "dia": 92}, 2)
    await post(client, auth_headers, "blood_pressure", {"sys": 132, "dia": 86}, 20)
    t = (await client.get("/insights/trends", headers=auth_headers)).json()
    bp = t["clinical"]["blood_pressure"]
    assert [(p["sys"], p["dia"]) for p in bp["points"]] == [(132, 86), (145, 92)]  # lama ke baru
    assert [p["category"] for p in bp["points"]] == ["prehypertension", "hypertension"]
    assert bp["latest"]["sys"] == 145 and bp["trend"] == "naik" and bp["count"] == 2
    refs = {r["label"]: r["value"] for r in bp["references"]}
    assert refs["Hipertensi (sistolik)"] == 140 and refs["Hipertensi (diastolik)"] == 90


async def test_tren_gula_darah_memisahkan_puasa_dan_sewaktu_dan_hba1c(client, auth_headers):
    await post(client, auth_headers, "fasting_glucose", {"mg_dl": 118}, 30)
    await post(client, auth_headers, "fasting_glucose", {"mg_dl": 104}, 3)
    await post(client, auth_headers, "random_glucose", {"mg_dl": 160}, 5)
    await post(client, auth_headers, "hba1c", {"percent": 5.9}, 10)
    c = (await client.get("/insights/trends", headers=auth_headers)).json()["clinical"]
    assert [p["value"] for p in c["fasting_glucose"]["points"]] == [118, 104]
    assert [p["range"] for p in c["fasting_glucose"]["points"]] == ["prediabetes", "prediabetes"]
    assert c["fasting_glucose"]["trend"] == "turun"  # selisih 14 >= 10
    assert [p["value"] for p in c["random_glucose"]["points"]] == [160]
    assert c["random_glucose"]["trend"] is None  # satu titik: belum ada tren
    assert c["hba1c"]["latest"]["value"] == 5.9


async def test_hasil_lebih_lama_dari_jendela_tidak_ikut(client, auth_headers):
    await post(client, auth_headers, "fasting_glucose", {"mg_dl": 120}, 400)
    c = (await client.get("/insights/trends", headers=auth_headers)).json()["clinical"]
    assert c["fasting_glucose"]["points"] == []


async def test_deret_harian_lengkap_per_hari_dengan_acuan_batas(client, session_maker):
    h = await raka_headers(client, session_maker)
    t = (await client.get("/insights/trends?days=14", headers=h)).json()
    daily = t["daily"]
    assert len(daily) == 14 and daily[0]["date"] < daily[-1]["date"]
    logged = [d for d in daily if d["logged"]]
    assert len(logged) >= 10
    assert all(d["sugar_g"] >= 0 for d in logged)
    assert any(d["sleep_hours"] == 5.0 for d in daily)
    assert t["references"]["sugar_g"] == 50 and t["references"]["active_minutes"] == 30


async def test_hari_tanpa_catatan_ditandai_tidak_tercatat_bukan_nol(client, auth_headers):
    daily = (await client.get("/insights/trends?days=7", headers=auth_headers)).json()["daily"]
    assert len(daily) == 7
    assert all(d["logged"] is False and d["sugar_g"] is None and d["sleep_hours"] is None for d in daily)


async def test_penanda_triase_ikut_dan_tidak_mendiagnosis(client, auth_headers):
    await post(client, auth_headers, "blood_pressure", {"sys": 150, "dia": 95}, 1)
    flags = (await client.get("/insights/trends", headers=auth_headers)).json()["triage"]
    assert flags[0]["level"] == "perhatian" and "bukan diagnosis" in flags[0]["text"].lower()


async def test_pengguna_baru_tidak_error_dan_diberi_catatan_info(client, auth_headers):
    t = (await client.get("/insights/trends", headers=auth_headers)).json()
    assert all(v["points"] == [] and v["latest"] is None for v in t["clinical"].values())
    assert [f["level"] for f in t["triage"]] == ["info"]


async def test_data_pengguna_lain_tidak_bocor_dan_butuh_login(client, auth_headers):
    await post(client, auth_headers, "fasting_glucose", {"mg_dl": 130}, 1)
    other = await client.post("/auth/register", json={"phone": "081200000055", "username": "orang_lain", "consent": True, "pin": "654321"})
    oh = {"Authorization": f"Bearer {other.json()['access_token']}"}
    assert (await client.get("/insights/trends", headers=oh)).json()["clinical"]["fasting_glucose"]["points"] == []
    assert (await client.get("/insights/trends")).status_code == 401
    assert (await client.get("/insights/trends?days=0", headers=auth_headers)).status_code == 422
    assert (await client.get("/insights/trends?days=91", headers=auth_headers)).status_code == 422
