import uuid
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.models import Log, LogItem
from app.repos import foods as foods_repo
from app.repos import logs as logs_repo
from app.schemas.api import ItemPatch, LogItemOut, LogOut, LogPatch
from app.security import current_user_id
from app.services.nutrition_items import item_data
from app.timeutil import local_date, utcnow

router = APIRouter(prefix="/logs", tags=["logs"])


def _out(log: Log, items: list[LogItem]) -> LogOut:
    return LogOut(
        id=str(log.id), kind=log.kind, source=log.source, occurred_at=log.occurred_at, raw_text=log.raw_text,
        extracted=log.extracted, corrected=log.corrected,
        items=[LogItemOut(id=str(i.id), name=i.name, portion_g=i.portion_g, sugar_g=i.sugar_g,
                          sodium_mg=i.sodium_mg, fat_g=i.fat_g, kcal=i.kcal, food_id=i.food_id, group=i.group_name)
               for i in items],
    )


@router.get("")
async def list_logs(
    date_: date | None = Query(default=None, alias="date"),
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    day = date_ or local_date(utcnow())
    rows = await logs_repo.on_date(session, user_id, day)
    return {"date": day.isoformat(), "logs": [_out(lg, items) for lg, items in rows]}


FREQUENT_MIN_COUNT = 2


@router.get("/frequent")
async def frequent_foods(
    days: int = Query(default=60, ge=7, le=180),
    limit: int = Query(default=8, ge=1, le=20),
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Makanan dan minuman yang sering dicatat, supaya mencatat ulang cukup satu ketukan. Hanya yang muncul minimal 2 kali."""
    cutoff = utcnow() - timedelta(days=days)
    last = func.max(Log.occurred_at)
    rows = (
        await session.execute(
            select(LogItem.name, Log.kind, func.count().label("n"), last.label("last_at"),
                   func.avg(LogItem.portion_g).label("avg_portion"))
            .join(Log, Log.id == LogItem.log_id)
            .where(Log.user_id == user_id, Log.kind.in_(("meal", "drink")), Log.occurred_at >= cutoff,
                   func.length(func.trim(LogItem.name)) > 0)
            .group_by(LogItem.name, Log.kind)
            .having(func.count() >= FREQUENT_MIN_COUNT)
            .order_by(func.count().desc(), last.desc())
            .limit(limit)
        )
    ).all()
    return {
        "foods": [
            {"name": name, "kind": kind, "count": n, "last_at": at.isoformat(),
             "portion_g": round(float(avg), 0) if avg is not None else None}
            for name, kind, n, at, avg in rows
        ]
    }


async def _scaled_label_items(session: AsyncSession, log: Log, patches: list) -> list[logs_repo.ItemData]:
    """Log dari label kemasan: angkanya tercetak, bukan dari tabel pangan. Koreksi porsi menskalakan angka itu
    secara proporsional (nama tidak dicocokkan ulang, supaya gizi tidak hilang)."""
    existing = {i.name.lower(): i for i in (await logs_repo._with_items(session, [log]))[0][1]}
    out: list[logs_repo.ItemData] = []
    for p in patches:
        old = existing.get(p.name.lower())
        if old is None or p.portion_g is None or not old.portion_g:
            out.append(logs_repo.ItemData(name=p.name, portion_g=p.portion_g))
            continue
        ratio = p.portion_g / old.portion_g
        scale = lambda v: None if v is None else v * ratio  # noqa: E731
        out.append(logs_repo.ItemData(name=old.name, portion_g=p.portion_g, sugar_g=scale(old.sugar_g),
                                      sodium_mg=scale(old.sodium_mg), fat_g=scale(old.fat_g), kcal=scale(old.kcal)))
    return out


@router.patch("/{log_id}", response_model=LogOut)
async def patch_log(
    log_id: uuid.UUID,
    body: LogPatch,
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> LogOut:
    log = await logs_repo.get_owned(session, user_id, log_id)
    if log is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Catatan tidak ditemukan")
    patches = body.items if body.items is not None else await _current_as_patches(session, log)
    if body.scale is not None:
        patches = [_scaled(p, body.scale) if body.group is None or p.group == body.group else p for p in patches]
    if log.source in {"photo_label", "barcode"}:  # angka tercetak di kemasan, bukan dari tabel pangan
        new_items = await _scaled_label_items(session, log, patches)
    else:
        catalog = await foods_repo.catalog(session)
        new_items = [
            item_data(p.name, catalog.find_food(p.name, p.food_id), p.portion_g, group_name=p.group) for p in patches
        ]
    rows = await logs_repo.replace_items(session, log, new_items)
    return _out(log, rows)


async def _current_as_patches(session: AsyncSession, log: Log) -> list[ItemPatch]:
    items = (await logs_repo._with_items(session, [log]))[0][1]
    return [ItemPatch(name=i.name, portion_g=i.portion_g, food_id=i.food_id, group=i.group_name) for i in items]


def _scaled(p: ItemPatch, scale: float) -> ItemPatch:
    return p.model_copy(update={"portion_g": None if p.portion_g is None else p.portion_g * scale})
