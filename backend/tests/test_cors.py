import httpx

from app.main import app


async def preflight(origin: str):
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as client:
        return await client.options(
            "/profile",
            headers={
                "Origin": origin,
                "Access-Control-Request-Method": "GET",
                "Access-Control-Request-Headers": "authorization",
            },
        )


async def test_preflight_allowed_origin():
    resp = await preflight("http://localhost:8080")
    assert resp.status_code == 200
    assert resp.headers["access-control-allow-origin"] in ("http://localhost:8080", "*")
    assert "authorization" in resp.headers["access-control-allow-headers"].lower()


async def test_cors_origins_come_from_settings(monkeypatch):
    from app.config import settings

    assert settings.cors_origins, "daftar origin CORS tidak boleh kosong"
