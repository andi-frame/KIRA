import httpx
import pytest
from sqlalchemy.ext.asyncio import async_sessionmaker

from app.db import get_session, get_session_factory
from app.main import app
from app.ratelimit import login_limiter


@pytest.fixture(autouse=True)
def _fresh_limiter():
    login_limiter.clear()
    yield
    login_limiter.clear()


@pytest.fixture
async def client(engine):
    maker = async_sessionmaker(engine, expire_on_commit=False)

    async def override_session():
        async with maker() as session:
            yield session

    app.dependency_overrides[get_session] = override_session
    app.dependency_overrides[get_session_factory] = lambda: maker
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
async def auth_headers(client):
    resp = await client.post("/auth/register", json={"phone": "081200000001", "pin": "123456"})
    assert resp.status_code == 200, resp.text
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}
