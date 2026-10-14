import uuid
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.nutrition import match_food
from app.db import get_session
from app.models import Log, LogItem
from app.repos import foods as foods_repo
from app.repos import logs as logs_repo
from app.schemas.api import LogItemOut, LogOut, LogPatch
from app.security import current_user_id
from app.services.nutrition_items import item_data
from app.timeutil import local_date, utcnow

router = APIRouter(prefix="/logs", tags=["logs"])


def _out(log: Log, items: list[LogItem]) -> LogOut:
    return LogOut(
        id=str(log.id), kind=log.kind, source=log.source, occurred_at=log.occurred_at, raw_text=log.raw_text,
        extracted=log.extracted, corrected=log.corrected,
        items=[LogItemOut(id=str(i.id), name=i.name, portion_g=i.portion_g, sugar_g=i.sugar_g,
                          sodium_mg=i.sodium_mg, fat_g=i.fat_g, kcal=i.kcal) for i in items],
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
    foods = await foods_repo.all_foods(session)
    new_items = [item_data(p.name, match_food(p.name, foods), p.portion_g) for p in body.items]
    rows = await logs_repo.replace_items(session, log, new_items)
    return _out(log, rows)
