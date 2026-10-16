import uuid
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.models import Log, LogItem
from app.repos import logs as logs_repo
from app.schemas.api import LogItemOut, LogOut, LogPatch
from app.security import current_user_id
from app.services import history as history_service
from app.services import log_edit
from app.timeutil import local_date, utcnow

router = APIRouter(prefix="/logs", tags=["logs"])


def log_out(log: Log, items: list[LogItem]) -> LogOut:
    return LogOut(
        id=str(log.id), kind=log.kind, source=log.source, occurred_at=log.occurred_at, raw_text=log.raw_text,
        extracted=log.extracted, corrected=log.corrected, meal_slot=log.meal_slot, slot_confirmed=log.slot_confirmed,
        halved_groups=log_edit.halved_groups(log),
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
    return {"date": day.isoformat(), "logs": [log_out(lg, items) for lg, items in rows]}


@router.get("/history")
async def history(
    days: int = Query(default=14, ge=1, le=history_service.MAX_DAYS),
    before: date | None = Query(default=None),
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Riwayat makan per hari (terbaru dulu) dengan gizi tiap item, total harian, dan batas harian sesuai mode."""
    return await history_service.meal_history(session, user_id, days, before)


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


@router.get("/batch")
async def logs_batch(
    ids: str = Query(description="id catatan dipisah koma (maksimal 50)"),
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Catatan milik pengguna dengan id tertentu (untuk memulihkan kartu di obrolan). Id yang bukan miliknya atau sudah
    dihapus diabaikan."""
    wanted = [i for i in ids.split(",") if i][:50]
    try:
        rows = await logs_repo.by_ids(session, user_id, wanted)
    except ValueError:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "Id catatan tidak valid") from None
    return {"logs": [log_out(lg, items) for lg, items in rows]}


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
    try:
        if log.kind in {"meal", "drink"} and (body.items is not None or body.scale is not None or body.half is not None):
            await log_edit.edit_meal_items(session, log, items=body.items, scale=body.scale, group=body.group, half=body.half)
        if body.meal_slot is not None:
            log_edit.set_meal_slot(log, body.meal_slot)
        if body.count is not None:
            await log_edit.set_drink_count(session, log, body.count)
        if any(v is not None for v in (body.minutes, body.activity_kind, body.hours, body.bed_time, body.wake_time)):
            log_edit.update_fields(log, minutes=body.minutes, activity_kind=body.activity_kind, hours=body.hours,
                                   bed_time=body.bed_time, wake_time=body.wake_time)
        if body.occurred_at is not None:
            if body.occurred_at > utcnow() + timedelta(minutes=5):
                raise log_edit.EditError("Waktu catatan tidak boleh di masa depan.")
            log_edit.move_to(log, body.occurred_at)
    except log_edit.EditError as exc:
        await session.rollback()
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, str(exc)) from None
    log.corrected = True
    await log_edit.refresh_after_change(session, user_id)
    await session.commit()
    await session.refresh(log)
    return log_out(log, (await logs_repo._with_items(session, [log]))[0][1])


@router.delete("/{log_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_log(
    log_id: uuid.UUID,
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> None:
    """Hapus satu catatan. Proyeksi, total harian, tren, dan rencana dihitung dari catatan, jadi ikut berubah."""
    log = await logs_repo.get_owned(session, user_id, log_id)
    if log is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Catatan tidak ditemukan")
    await log_edit.delete_log(session, log)
    await log_edit.refresh_after_change(session, user_id)
    await session.commit()
