import os
import re
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
    "risk_snapshots", "weekly_summaries", "messages", "check_recommendations", "faskes", "dishes",
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


async def test_seed_uses_tkpi_values_where_a_tkpi_entry_exists(engine):
    async with engine.connect() as conn:
        rows = {
            r.id: r
            for r in (await conn.execute(text("select id, per100g, tkpi_code, source_note from foods"))).all()
        }
    nasi, rendang, boba = rows["nasi_putih"], rows["rendang"], rows["boba_milk_tea"]
    assert nasi.tkpi_code == "AP001"
    assert nasi.per100g["kcal"] == 180 and nasi.per100g["fat_g"] == 0.3 and nasi.per100g["sodium_mg"] == 1
    assert rendang.tkpi_code == "FP062"
    assert rendang.per100g["fat_g"] == 7.9 and rendang.per100g["kcal"] == 193
    assert "natrium: estimasi" in rendang.source_note  # TKPI tidak memuat natrium rendang
    assert boba.tkpi_code is None and "estimasi" in boba.source_note.lower()


async def test_sugar_is_always_flagged_as_estimate_because_tkpi_has_no_sugar(engine):
    from seed.load import _component_rows

    components = {r["id"] for r in _component_rows()}
    async with engine.connect() as conn:
        rows = (await conn.execute(text("select id, source_note from foods"))).all()
    assert rows and all("gula: estimasi" in note for fid, note in rows if fid not in components)
    # komponen: gula dari USDA (bersumber) atau ditandai estimasi, tidak pernah tanpa asal
    sugar_origin = re.compile(r"(USDA FoodData Central[^;]*|Estimasi KIRA): [^;]*gula")
    assert all(sugar_origin.search(note) for fid, note in rows if fid in components)
