"""Persona demo: Raka, 28 tahun, software engineer. SEMUA DATA DUMMY.

Kerja ±50 jam/minggu, tidur ±5 jam, kopi susu gula aren hampir tiap hari, ayah diabetes,
belum pernah cek gula darah. 21 hari riwayat (kemarin dan sebelumnya); hari ini sengaja kosong
agar check-in live di panggung.

Pakai: python -m seed.raka [--reset]
"""
import asyncio
import sys
import uuid
from datetime import date, datetime, timedelta

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from app.config import settings
from app.core_calc.nutrition import match_food
from app.repos import foods as foods_repo
from app.repos import logs as logs_repo
from app.repos import profiles, users
from app.schemas.profile import ProfileIn
from app.security import hash_pin
from app.services.nutrition_items import item_data
from app.timeutil import WIB, utcnow

RAKA_PHONE = "081234567890"  # dummy
RAKA_PIN = "123456"
HISTORY_DAYS = 21

LUNCHES = [
    [("nasi putih", 200), ("rendang", 70)],
    [("nasi goreng", 220), ("telur ceplok", 50)],
    [("mie instan goreng", 200)],
    [("nasi putih", 200), ("ayam goreng", 80), ("tempe goreng", 40)],
    [("nasi putih", 200), ("rendang", 70), ("perkedel", 40)],
    [("gado gado", 250)],
    [("bakso", 250)],
]
DINNERS = [
    [("martabak telur", 150)],
    [("nasi putih", 150), ("ikan goreng", 80)],
    [("seblak", 200)],
    [("nasi uduk", 200), ("ayam goreng", 80)],
]


def _at(day_offset: int, hour: int, minute: int = 0) -> datetime:
    """Waktu WIB pada hari (hari ini - day_offset), dalam UTC."""
    today: date = utcnow().astimezone(WIB).date()
    local = datetime.combine(today - timedelta(days=day_offset), datetime.min.time(), tzinfo=WIB)
    return (local + timedelta(hours=hour, minutes=minute)).astimezone(utcnow().tzinfo)


async def reset_raka(session: AsyncSession) -> None:
    """Hapus Raka beserta semua datanya (cascade) agar demo bisa diulang dari keadaan awal."""
    await session.execute(text("delete from users where phone = :phone"), {"phone": RAKA_PHONE})
    await session.commit()


async def create_raka(session: AsyncSession) -> uuid.UUID:
    existing = await users.get_by_phone(session, RAKA_PHONE)
    if existing is not None:
        return existing.id
    user = await users.create(session, RAKA_PHONE, hash_pin(RAKA_PIN))
    await profiles.update(
        session,
        user.id,
        ProfileIn(
            display_name="Raka", birth_date=date(utcnow().astimezone(WIB).year - 28, 3, 14), sex="male",
            height_cm=170, weight_kg=78, family_history_diabetes="first_degree", smoker=False,
            on_bp_medication=False, usual_active_30min=False, usual_veg_fruit=True,
        ),
    )
    foods = await foods_repo.all_foods(session)

    async def meal(day: int, hour: int, picks: list[tuple[str, int]]) -> None:
        items = [item_data(name, match_food(name, foods), grams) for name, grams in picks]
        await logs_repo.add_log(
            session, user.id, kind="meal", source="text", occurred_at=_at(day, hour),
            extracted={"items": [{"name": n, "portion_g_guess": g} for n, g in picks]},
            raw_text=", ".join(n for n, _ in picks), items=items, commit=False,
        )

    async def drink(day: int, hour: int, name: str, count: float) -> None:
        await logs_repo.add_log(
            session, user.id, kind="drink", source="text", occurred_at=_at(day, hour),
            extracted={"name": name, "size": "gelas", "count": count}, raw_text=name,
            items=[item_data(name, match_food(name, foods), None, multiplier=count)], commit=False,
        )

    for d in range(1, HISTORY_DAYS + 1):
        await drink(d, 8, "kopi susu gula aren", 2 if d % 7 in (1, 3, 5) else 1)
        await meal(d, 12, LUNCHES[d % len(LUNCHES)])
        if d % 3 != 0:
            await drink(d, 14, "es teh manis", 1)
        await meal(d, 20, DINNERS[d % len(DINNERS)])
        await logs_repo.add_log(
            session, user.id, kind="sleep", source="text", occurred_at=_at(d, 7),
            extracted={"bed_time": "01:30", "wake_time": "06:30", "hours": 5.0}, raw_text="tidur jam setengah dua",
            items=[], commit=False,
        )
        if d % 7 == 2:
            await logs_repo.add_log(
                session, user.id, kind="activity", source="text", occurred_at=_at(d, 18),
                extracted={"kind": "jalan kaki", "minutes": 15}, raw_text="jalan kaki 15 menit",
                items=[], commit=False,
            )
    await session.commit()
    return user.id


async def _main() -> None:
    from sqlalchemy.ext.asyncio import async_sessionmaker

    engine = create_async_engine(settings.database_url)
    try:
        async with async_sessionmaker(engine, expire_on_commit=False)() as session:
            if "--reset" in sys.argv:
                await reset_raka(session)
            uid = await create_raka(session)
        print(f"Raka siap: user {uid}, login {RAKA_PHONE} / PIN {RAKA_PIN} (data dummy)")
    finally:
        await engine.dispose()


if __name__ == "__main__":
    asyncio.run(_main())
