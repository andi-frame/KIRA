from datetime import timedelta

from sqlalchemy import text

from app.timeutil import utcnow
from tests.api.test_family import MEMBER_PHONE, active_link, register
from tests.api.test_summary import raka_headers


def token_of(url: str) -> str:
    return url.rsplit("/s/", 1)[1].split("/")[0]


async def make_link(client, headers, **body):
    r = await client.post("/summary/share", json=body, headers=headers)
    assert r.status_code == 200, r.text
    return r.json()


async def test_tautan_dibuat_dengan_masa_berlaku_dan_token_hanya_terlihat_sekali(client, auth_headers, engine):
    link = await make_link(client, auth_headers, days=30, valid_days=7)
    assert "/s/" in link["url"] and link["pdf_url"].endswith("/ringkasan.pdf")
    token = token_of(link["url"])
    assert len(token) > 40
    listed = (await client.get("/summary/share", headers=auth_headers)).json()["links"]
    assert [x["id"] for x in listed] == [link["id"]] and "url" not in listed[0]  # daftar tidak membocorkan tautan
    async with engine.connect() as conn:
        stored = (await conn.execute(text("select token_hash from share_links"))).scalar_one()
    assert token not in stored and len(stored) == 64


async def test_penerima_membuka_halaman_tanpa_akun_dan_halaman_tidak_boleh_di_cache_atau_diindeks(client, session_maker):
    h = await raka_headers(client, session_maker)
    link = await make_link(client, h, days=30)
    r = await client.get(f"/s/{token_of(link['url'])}")
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/html")
    assert r.headers["cache-control"] == "no-store" and "noindex" in r.headers["x-robots-tag"]
    page = r.text
    assert "Ringkasan KIRA untuk dokter" in page and "Raka" in page and "bukan diagnosis" in page
    assert "Penanda untuk perhatian" in page and "Hasil pemeriksaan terakhir" in page
    assert "<script" not in page and "http://" not in page.replace("http://www.w3.org", "")
    assert "081234567890" not in page  # tidak memuat nomor HP


async def test_pdf_lewat_tautan_valid_dan_memuat_grafik(client, session_maker):
    h = await raka_headers(client, session_maker)
    link = await make_link(client, h, days=14)
    r = await client.get(f"/s/{token_of(link['url'])}/ringkasan.pdf")
    assert r.status_code == 200 and r.content[:5] == b"%PDF-"
    assert r.headers["cache-control"] == "no-store"


async def test_tautan_salah_kedaluwarsa_atau_dicabut_diperlakukan_sama(client, auth_headers, engine):
    assert (await client.get("/s/" + "x" * 64)).status_code == 404
    link = await make_link(client, auth_headers)
    token = token_of(link["url"])
    assert (await client.get(f"/s/{token}")).status_code == 200
    async with engine.begin() as conn:
        await conn.execute(text("update share_links set expires_at = :t"), {"t": utcnow() - timedelta(seconds=1)})
    expired = await client.get(f"/s/{token}")
    unknown = await client.get("/s/" + "y" * 64)
    assert expired.status_code == unknown.status_code == 404
    assert expired.text == unknown.text and "tidak berlaku" in expired.text.lower()
    assert (await client.get(f"/s/{token}/ringkasan.pdf")).status_code == 404


async def test_pemilik_bisa_mencabut_dan_orang_lain_tidak(client, auth_headers):
    link = await make_link(client, auth_headers)
    other = await register(client, MEMBER_PHONE)
    assert (await client.delete(f"/summary/share/{link['id']}", headers=other)).status_code == 404
    assert (await client.get(f"/s/{token_of(link['url'])}")).status_code == 200
    assert (await client.delete(f"/summary/share/{link['id']}", headers=auth_headers)).status_code == 200
    assert (await client.get(f"/s/{token_of(link['url'])}")).status_code == 404
    shown = (await client.get("/summary/share", headers=auth_headers)).json()["links"][0]
    assert shown["revoked"] is True
    assert (await client.get("/summary/share", headers=other)).json()["links"] == []


async def test_batas_tautan_aktif_dan_pencabutan_membukanya_lagi(client, auth_headers):
    ids = [(await make_link(client, auth_headers))["id"] for _ in range(5)]
    over = await client.post("/summary/share", json={}, headers=auth_headers)
    assert over.status_code == 409 and "cabut" in over.json()["detail"].lower()
    await client.delete(f"/summary/share/{ids[0]}", headers=auth_headers)
    assert (await client.post("/summary/share", json={}, headers=auth_headers)).status_code == 200


async def test_masukan_dibatasi_dan_butuh_login(client, auth_headers):
    assert (await client.post("/summary/share", json={"valid_days": 31}, headers=auth_headers)).status_code == 422
    assert (await client.post("/summary/share", json={"valid_days": 0}, headers=auth_headers)).status_code == 422
    assert (await client.post("/summary/share", json={"days": 91}, headers=auth_headers)).status_code == 422
    assert (await client.post("/summary/share", json={})).status_code == 401
    assert (await client.get("/summary/share")).status_code == 401


async def test_pembukaan_dihitung_dan_tercatat_di_riwayat_akses_pemilik(client, auth_headers):
    link = await make_link(client, auth_headers)
    token = token_of(link["url"])
    await client.get(f"/s/{token}")
    await client.get(f"/s/{token}")
    shown = (await client.get("/summary/share", headers=auth_headers)).json()["links"][0]
    assert shown["open_count"] == 2 and shown["last_opened_at"]
    entries = (await client.get("/account/access-log", headers=auth_headers)).json()["entries"]
    assert len(entries) == 1  # dua pembukaan beruntun dilipat jadi satu catatan
    assert entries[0]["kind"] == "share_link" and entries[0]["viewer"] == "Penerima tautan"


async def test_anggota_keluarga_yang_membuka_status_tercatat_untuk_pemilik(client, auth_headers):
    member = await register(client, MEMBER_PHONE)
    link_id = await active_link(client, auth_headers, member)
    await client.put("/profile", json={"display_name": "Bu Sari"}, headers=member)
    assert (await client.get(f"/family/{link_id}/status", headers=member)).status_code == 200
    await client.get(f"/family/{link_id}/status", headers=member)
    entries = (await client.get("/account/access-log", headers=auth_headers)).json()["entries"]
    assert [(e["kind"], e["viewer"]) for e in entries] == [("family_status", "Bu Sari")]
    assert (await client.get("/account/access-log", headers=member)).json()["entries"] == []  # milik pemilik saja
    assert (await client.get("/account/access-log")).status_code == 401


async def test_riwayat_akses_tetap_terbaca_setelah_akun_pelihat_dihapus(client, auth_headers):
    member = await register(client, MEMBER_PHONE)
    link_id = await active_link(client, auth_headers, member)
    await client.get(f"/family/{link_id}/status", headers=member)
    await client.post("/account/delete", json={"pin": "123456"}, headers=member)
    entries = (await client.get("/account/access-log", headers=auth_headers)).json()["entries"]
    assert len(entries) == 1 and entries[0]["viewer"]
