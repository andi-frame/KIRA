import os
import subprocess
import sys
from pathlib import Path

import httpx
import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.config import settings
from app.db import get_session
from app.main import app
from seed.load import load_seed

BACKEND = Path(__file__).resolve().parents[2]


@pytest.fixture(scope="session", autouse=True)
def _schema():
    env = {**os.environ, "DATABASE_URL": settings.test_database_url}
    subprocess.run([sys.executable, "-m", "alembic", "upgrade", "head"], cwd=BACKEND, env=env, check=True)


@pytest.fixture
async def engine(_schema):
    eng = create_async_engine(settings.test_database_url)
    await load_seed(eng)
    yield eng
    async with eng.begin() as conn:
        await conn.execute(text("truncate users cascade"))
    await eng.dispose()


@pytest.fixture
async def client(engine):
    maker = async_sessionmaker(engine, expire_on_commit=False)

    async def override():
        async with maker() as session:
            yield session

    app.dependency_overrides[get_session] = override
    transport = httpx.ASGITransport(app=app)
    async with httpx.AsyncClient(transport=transport, base_url="http://test") as c:
        yield c
    app.dependency_overrides.clear()


@pytest.fixture
async def auth_headers(client):
    resp = await client.post("/auth/register", json={"phone": "081200000001", "pin": "123456"})
    assert resp.status_code == 200, resp.text
    return {"Authorization": f"Bearer {resp.json()['access_token']}"}
