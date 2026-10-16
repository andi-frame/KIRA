"""Riwayat makan dan gizi per hari (tanggal WIB): apa yang dimakan/diminum, gizinya, dan batas harian sesuai mode.

Semua angka dijumlah dari log_items (gizi dari tabel pangan atau label kemasan); hari tanpa catatan ditandai
logged=false ("tidak tercatat"), bukan nol.
"""
import uuid
from collections import defaultdict
from datetime import date, datetime, time, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.constants import DAILY_LIMITS, DAILY_LIMITS_MANAGEMENT
from app.models import Log, LogItem, User
from app.timeutil import WIB, local_date, utcnow

NUTRIENTS = ("kcal", "sugar_g", "sodium_mg", "fat_g")
MAX_DAYS = 60


def limits_for(mode: str) -> dict[str, float]:
    return dict(DAILY_LIMITS_MANAGEMENT if mode == "management" else DAILY_LIMITS)


def _totals(items: list[LogItem]) -> dict[str, float]:
    return {k: round(sum(float(getattr(i, k) or 0) for i in items), 1) for k in NUTRIENTS}


def _title(log: Log, items: list[LogItem]) -> str:
    if log.kind == "drink":
        name = log.extracted.get("name") or (items[0].name if items else "Minuman")
        count = float(log.extracted.get("count", 1) or 1)
        return f"{count:g}x {name}" if count != 1 else name
    names: list[str] = []
    for i in items:
        label = i.group_name or i.name
        if label not in names:
            names.append(label)
    return ", ".join(names) or "Makan"


def meal_view(log: Log, items: list[LogItem]) -> dict:
    return {
        "log_id": str(log.id),
        "kind": log.kind,
        "time": log.occurred_at.astimezone(WIB).isoformat(),
        "source": log.source,
        "title": _title(log, items),
        "items": [
            {"id": str(i.id), "name": i.name, "group": i.group_name, "portion_g": i.portion_g, "kcal": i.kcal,
             "sugar_g": i.sugar_g, "sodium_mg": i.sodium_mg, "fat_g": i.fat_g, "food_id": i.food_id}
            for i in items
        ],
        "totals": _totals(items),
        "uncounted": sum(1 for i in items if i.kcal is None),
        "corrected": log.corrected,
    }


async def logs_between(session: AsyncSession, user_id: uuid.UUID, start: date, end: date) -> list[tuple[Log, list[LogItem]]]:
    """Log pengguna dari awal `start` sampai akhir `end` (tanggal WIB, inklusif), urut waktu, beserta itemnya."""
    lo = datetime.combine(start, time.min, tzinfo=WIB)
    hi = datetime.combine(end + timedelta(days=1), time.min, tzinfo=WIB)
    logs = (await session.execute(
        select(Log).where(Log.user_id == user_id, Log.occurred_at >= lo, Log.occurred_at < hi)
        .order_by(Log.occurred_at, Log.id)
    )).scalars().all()
    by_log: dict[uuid.UUID, list[LogItem]] = defaultdict(list)
    if logs:
        rows = (await session.execute(
            select(LogItem).where(LogItem.log_id.in_([lg.id for lg in logs])).order_by(LogItem.id)
        )).scalars().all()
        for item in rows:
            by_log[item.log_id].append(item)
    return [(lg, by_log[lg.id]) for lg in logs]


def day_summary(day: date, rows: list[tuple[Log, list[LogItem]]], limits: dict[str, float]) -> dict:
    meals = [meal_view(lg, items) for lg, items in rows if lg.kind == "meal"]
    drinks = [meal_view(lg, items) for lg, items in rows if lg.kind == "drink"]
    eaten = [i for lg, items in rows if lg.kind in ("meal", "drink") for i in items]
    activity = [float(lg.extracted.get("minutes", 0) or 0) for lg, _ in rows if lg.kind == "activity"]
    sleep = [float(lg.extracted["hours"]) for lg, _ in rows if lg.kind == "sleep" and lg.extracted.get("hours")]
    return {
        "date": day.isoformat(),
        "logged": bool(rows),
        "totals": _totals(eaten),
        "limits": limits,
        "meals": meals,
        "drinks": drinks,
        "activity_minutes": round(sum(activity), 1) if activity else None,
        "sleep_hours": round(max(sleep), 1) if sleep else None,
    }


async def meal_history(session: AsyncSession, user_id: uuid.UUID, days: int = 14, before: date | None = None) -> dict:
    """`days` hari sebelum `before` (eksklusif; bawaan: sampai hari ini), terbaru dulu. `next_before` untuk halaman
    berikutnya (lebih lama)."""
    today = local_date(utcnow())
    end = min(before - timedelta(days=1), today) if before else today
    start = end - timedelta(days=days - 1)
    user = await session.get(User, user_id)
    limits = limits_for(user.mode if user else "prevention")
    by_day: dict[date, list] = defaultdict(list)
    for lg, items in await logs_between(session, user_id, start, end):
        by_day[local_date(lg.occurred_at)].append((lg, items))
    out = [day_summary(start + timedelta(days=o), by_day.get(start + timedelta(days=o), []), limits)
           for o in range(days)]
    return {"days": list(reversed(out)), "next_before": start.isoformat()}
