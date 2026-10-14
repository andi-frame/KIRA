import os
import subprocess
import sys
from pathlib import Path

import pytest
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine

from app.config import settings
from seed.load import load_seed

BACKEND = Path(__file__).resolve().parent.parent
EXPECTED_TABLES = {
    "users", "health_profiles", "foods", "logs", "log_items", "clinical_results", "diagnoses",
    "risk_snapshots", "weekly_summaries", "messages", "check_recommendations", "faskes",
}


def alembic(*args: str) -> None:
    env = {**os.environ, "DATABASE_URL": settings.test_database_url}
    subprocess.run([sys.executable, "-m", "alembic", *args], cwd=BACKEND, env=env, check=True)


@pytest.fixture(scope="module", autouse=True)
def migrated():
    alembic("downgrade", "base")
    alembic("upgrade", "head")
    yield


@pytest.fixture
async def engine():
    eng = create_async_engine(settings.test_database_url)
    yield eng
    await eng.dispose()


async def test_all_tables_exist(engine):
    async with engine.connect() as conn:
        rows = await conn.execute(
            text("select table_name from information_schema.tables where table_schema='public'")
        )
    assert EXPECTED_TABLES <= {r[0] for r in rows}


async def test_seed_is_idempotent_and_has_local_foods(engine):
    async def count(table: str) -> int:
        async with engine.connect() as conn:
            return (await conn.execute(text(f"select count(*) from {table}"))).scalar_one()

    await load_seed(engine)
    foods_first, faskes_first = await count("foods"), await count("faskes")
    await load_seed(engine)
    assert (await count("foods"), await count("faskes")) == (foods_first, faskes_first)
    assert foods_first >= 90
    assert faskes_first >= 5

    async with engine.connect() as conn:
        aliases = (await conn.execute(text("select unnest(aliases) from foods"))).scalars().all()
    assert "es teh" in aliases
    assert "kopi susu gula aren" in aliases
