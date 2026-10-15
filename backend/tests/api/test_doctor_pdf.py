import io
from datetime import datetime, timedelta, timezone

from pypdf import PdfReader

from tests.api.test_summary import raka_headers


def ago(days: int) -> str:
    return (datetime.now(timezone.utc) - timedelta(days=days)).isoformat()


def text_of(resp) -> str:
    reader = PdfReader(io.BytesIO(resp.content))
    return "\n".join(page.extract_text() for page in reader.pages)


def pages_of(resp) -> int:
    return len(PdfReader(io.BytesIO(resp.content)).pages)


async def post(client, h, kind, value, days_ago):
    r = await client.post("/results", json={"kind": kind, "value": value, "source": "self", "measured_at": ago(days_ago)}, headers=h)
    assert r.status_code == 200, r.text


async def test_pdf_berisi_ringkasan_penanda_tabel_hasil_dan_semua_grafik(client, session_maker):
    h = await raka_headers(client, session_maker)
    await post(client, h, "blood_pressure", {"sys": 132, "dia": 86}, 20)
    await post(client, h, "blood_pressure", {"sys": 150, "dia": 95}, 2)
    await post(client, h, "fasting_glucose", {"mg_dl": 118}, 15)
    await post(client, h, "fasting_glucose", {"mg_dl": 128}, 3)
    r = await client.get("/summary/doctor.pdf?days=30", headers=h)
    assert r.status_code == 200
    assert r.headers["content-type"] == "application/pdf"
    assert r.headers["content-disposition"].startswith("attachment; filename=\"kira-ringkasan-")
    assert r.content.startswith(b"%PDF")
    assert 1 <= pages_of(r) <= 3
    t = text_of(r)
    for expected in [
        "Ringkasan KIRA untuk dokter", "Raka", "Penanda untuk perhatian", "PERLU PERHATIAN", "150/95",
        "Hasil pemeriksaan terakhir", "Tren tekanan darah", "Tren gula darah puasa",
        "Gula dari makan dan minum per hari", "Jam tidur per malam", "Menit aktif per hari",
        "bukan diagnosis", "Sumber",
    ]:
        assert expected in t, expected


async def test_pdf_tidak_memuat_nomor_hp_dan_menyebut_cakupan_data(client, session_maker):
    h = await raka_headers(client, session_maker)
    t = text_of(await client.get("/summary/doctor.pdf?days=14", headers=h))
    assert "081234567890" not in t
    assert "hari tercatat" in t


async def test_pdf_pengguna_baru_tidak_error_dan_jujur_belum_ada_data(client, auth_headers):
    r = await client.get("/summary/doctor.pdf", headers=auth_headers)
    assert r.status_code == 200 and r.content.startswith(b"%PDF")
    t = text_of(r)
    assert "Belum ada hasil pemeriksaan" in t and "Belum ada catatan" in t


async def test_pdf_butuh_login_dan_periode_valid(client, auth_headers):
    assert (await client.get("/summary/doctor.pdf")).status_code == 401
    assert (await client.get("/summary/doctor.pdf?days=0", headers=auth_headers)).status_code == 422
    assert (await client.get("/summary/doctor.pdf?days=91", headers=auth_headers)).status_code == 422


async def test_pdf_nama_dengan_karakter_di_luar_latin_tidak_menjatuhkan_pembuatan(client, auth_headers):
    await client.put("/profile", json={"display_name": "Dian 中文 \U0001f600"}, headers=auth_headers)
    r = await client.get("/summary/doctor.pdf", headers=auth_headers)
    assert r.status_code == 200 and r.content.startswith(b"%PDF")
