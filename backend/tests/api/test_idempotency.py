import pytest
from sqlalchemy import text

from tests.api.helpers import install_models, reset_models

KEY = "msg-0001-abcdef"


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    reset_models()


async def count(engine, table):
    async with engine.connect() as conn:
        return (await conn.execute(text(f"select count(*) from {table}"))).scalar_one()


async def test_pesan_yang_dikirim_ulang_dengan_kunci_sama_tidak_dicatat_dua_kali(client, auth_headers, engine):
    chat, extract = install_models()
    body = {"text": "tadi siang rendang, es teh manis"}
    first = await client.post("/chat/message", json=body, headers={**auth_headers, "Idempotency-Key": KEY})
    again = await client.post("/chat/message", json=body, headers={**auth_headers, "Idempotency-Key": KEY})
    assert first.status_code == again.status_code == 200
    assert again.json() == first.json()  # jawaban yang sama persis, termasuk id catatan
    assert await count(engine, "logs") == 3  # bukan 6
    assert len(extract.calls) == 1  # model tidak dipanggil lagi (hemat biaya)


async def test_kunci_berbeda_atau_tanpa_kunci_diproses_biasa(client, auth_headers, engine):
    install_models()
    body = {"text": "tadi siang rendang, es teh manis"}
    await client.post("/chat/message", json=body, headers={**auth_headers, "Idempotency-Key": KEY})
    await client.post("/chat/message", json=body, headers={**auth_headers, "Idempotency-Key": "msg-0002-abcdef"})
    await client.post("/chat/message", json=body, headers=auth_headers)
    assert await count(engine, "logs") == 9


async def test_kunci_yang_sama_milik_pengguna_lain_tidak_bentrok(client, auth_headers, engine):
    install_models()
    other = await client.post(
        "/auth/register", json={"phone": "081200000077", "username": "pengguna_dua", "pin": "123456", "consent": True}
    )
    oh = {"Authorization": f"Bearer {other.json()['access_token']}", "Idempotency-Key": KEY}
    body = {"text": "tadi siang rendang, es teh manis"}
    await client.post("/chat/message", json=body, headers={**auth_headers, "Idempotency-Key": KEY})
    r = await client.post("/chat/message", json=body, headers=oh)
    assert r.status_code == 200
    assert await count(engine, "logs") == 6  # masing-masing pengguna mencatat sendiri


@pytest.mark.parametrize("key", ["pendek", "x" * 81, "ada spasi di sini", "karakter/aneh/!!"])
async def test_kunci_tidak_valid_ditolak(client, auth_headers, key):
    install_models()
    r = await client.post("/chat/message", json={"text": "halo"}, headers={**auth_headers, "Idempotency-Key": key})
    assert r.status_code == 422


async def test_hasil_cek_yang_dikirim_ulang_tidak_tersimpan_dua_kali(client, auth_headers, engine):
    payload = {"kind": "blood_pressure", "value": {"sys": 128, "dia": 82}, "source": "self"}
    headers = {**auth_headers, "Idempotency-Key": "res-0001-abcdef"}
    first = await client.post("/results", json=payload, headers=headers)
    again = await client.post("/results", json=payload, headers=headers)
    assert first.status_code == again.status_code == 200
    assert again.json() == first.json()
    assert await count(engine, "clinical_results") == 1


async def test_kegagalan_tidak_disimpan_sehingga_bisa_dicoba_ulang(client, auth_headers, engine):
    headers = {**auth_headers, "Idempotency-Key": "res-0002-abcdef"}
    bad = await client.post("/results", json={"kind": "blood_pressure", "value": {"sys": 400, "dia": 80}}, headers=headers)
    assert bad.status_code == 422
    good = await client.post(
        "/results", json={"kind": "blood_pressure", "value": {"sys": 120, "dia": 80}, "source": "self"}, headers=headers
    )
    assert good.status_code == 200 and good.json()["saved"] is True
    assert await count(engine, "clinical_results") == 1


async def test_kunci_lama_dibersihkan_saat_menyimpan_yang_baru(client, auth_headers, engine):
    install_models()
    await client.post("/chat/message", json={"text": "halo"}, headers={**auth_headers, "Idempotency-Key": KEY})
    async with engine.begin() as conn:
        await conn.execute(text("update idempotency_keys set created_at = now() - interval '8 days'"))
    await client.post("/chat/message", json={"text": "halo lagi"}, headers={**auth_headers, "Idempotency-Key": "msg-0003-abcdef"})
    async with engine.connect() as conn:
        keys = (await conn.execute(text("select key from idempotency_keys"))).scalars().all()
    assert keys == ["msg-0003-abcdef"]
