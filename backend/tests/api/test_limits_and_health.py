import pytest

from app.ratelimit import SlidingWindowLimiter
from tests.api.helpers import install_models, reset_models


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    reset_models()


def test_pembatas_jendela_geser_menolak_setelah_batas_dan_melapor_waktu_tunggu():
    limiter = SlidingWindowLimiter(max_calls=3, window_seconds=60)
    assert [limiter.check("a") for _ in range(3)] == [None, None, None]
    wait = limiter.check("a")
    assert wait is not None and 0 < wait <= 60
    assert limiter.check("b") is None  # kunci lain tidak terpengaruh
    limiter.clear()
    assert limiter.check("a") is None


async def test_terlalu_banyak_pesan_per_menit_ditolak_dengan_retry_after(client, auth_headers):
    install_models()
    for _ in range(20):
        assert (await client.post("/chat/message", json={"text": "halo"}, headers=auth_headers)).status_code == 200
    r = await client.post("/chat/message", json={"text": "halo"}, headers=auth_headers)
    assert r.status_code == 429 and "Terlalu banyak pesan" in r.json()["detail"]
    assert int(r.headers["retry-after"]) >= 1


async def test_batas_per_pengguna_bukan_global(client, auth_headers):
    install_models()
    for _ in range(20):
        await client.post("/chat/message", json={"text": "halo"}, headers=auth_headers)
    other = await client.post(
        "/auth/register", json={"phone": "081200000091", "username": "pengguna_lain", "pin": "123456", "consent": True}
    )
    oh = {"Authorization": f"Bearer {other.json()['access_token']}"}
    assert (await client.post("/chat/message", json={"text": "halo"}, headers=oh)).status_code == 200


async def test_batas_juga_berlaku_untuk_suara_dan_foto_tetapi_bukan_untuk_baca_data(client, auth_headers):
    install_models()
    for _ in range(20):
        await client.post("/chat/message", json={"text": "halo"}, headers=auth_headers)
    photo = await client.post("/chat/photo?kind=food", files={"image": ("f.jpg", b"123", "image/jpeg")}, headers=auth_headers)
    voice = await client.post("/chat/voice", files={"audio": ("v.m4a", b"123", "audio/mp4")}, headers=auth_headers)
    assert photo.status_code == voice.status_code == 429
    assert (await client.get("/projection", headers=auth_headers)).status_code == 200  # hanya yang memanggil model


async def test_permintaan_tanpa_login_tetap_401_bukan_429(client):
    assert (await client.post("/chat/message", json={"text": "halo"})).status_code == 401


async def test_setiap_jawaban_membawa_x_request_id_dan_id_dari_klien_dipertahankan(client):
    r = await client.get("/health")
    assert len(r.headers["x-request-id"]) >= 8
    echoed = await client.get("/health", headers={"X-Request-ID": "abc-12345"})
    assert echoed.headers["x-request-id"] == "abc-12345"


async def test_health_ready_menyatakan_siap_saat_basis_data_terjangkau(client, monkeypatch):
    from app import main

    ready = await client.get("/health/ready")
    assert ready.status_code == 200 and ready.json() == {"status": "ready"}

    class Broken:
        async def __aenter__(self):
            raise ConnectionError("db mati")

        async def __aexit__(self, *a):
            return False

    monkeypatch.setattr(main, "SessionLocal", lambda: Broken())
    down = await client.get("/health/ready")
    assert down.status_code == 503 and down.json() == {"status": "not_ready"}
    assert (await client.get("/health")).status_code == 200  # liveness tidak bergantung pada basis data
