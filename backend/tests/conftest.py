import itertools
import os
import subprocess
import sys
from pathlib import Path

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.config import settings
from seed.load import load_seed

BACKEND = Path(__file__).resolve().parents[1]
_phone_counter = itertools.count(1)


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
def session_maker(engine):
    return async_sessionmaker(engine, expire_on_commit=False)


@pytest.fixture
def make_user(session_maker):
    """Membuat pengguna uji (opsional dengan profil) dan mengembalikan UUID-nya."""
    from app.repos import profiles, users
    from app.schemas.profile import ProfileIn

    async def _make(**profile_fields):
        phone = f"0812000{next(_phone_counter):05d}"
        async with session_maker() as session:
            user = await users.create(session, phone, "x")
            if profile_fields:
                await profiles.update(session, user.id, ProfileIn(**profile_fields))
            return user.id

    return _make
