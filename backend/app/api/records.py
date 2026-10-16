"""Rekam medis pribadi: daftar, tambah, ubah, hapus."""
import uuid
from datetime import date
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.models import MedicalRecord
from app.security import current_user_id
from app.services import medical_records as service

router = APIRouter(prefix="/records", tags=["records"])

Kind = Literal["diagnosis", "lab", "medication", "allergy", "procedure", "vaccination", "imaging", "visit", "other"]


class ValueIn(BaseModel):
    name: str = Field(min_length=1, max_length=80)
    value: str = Field(min_length=1, max_length=40)
    unit: str | None = Field(default=None, max_length=20)


class RecordIn(BaseModel):
    kind: Kind
    title: str = Field(min_length=1, max_length=120)
    recorded_on: date | None = None
    provider: str | None = Field(default=None, max_length=120)
    details: str | None = Field(default=None, max_length=2000)
    values: list[ValueIn] = Field(default=[], max_length=30)


class RecordPatch(BaseModel):
    kind: Kind | None = None
    title: str | None = Field(default=None, min_length=1, max_length=120)
    recorded_on: date | None = None
    provider: str | None = Field(default=None, max_length=120)
    details: str | None = Field(default=None, max_length=2000)
    values: list[ValueIn] | None = Field(default=None, max_length=30)


@router.get("")
async def list_records(
    kind: Kind | None = Query(default=None),
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    rows = await service.list_records(session, user_id, kind)
    return {"records": [service.record_out(r) for r in rows], "kinds": service.KIND_LABELS}


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_record(
    body: RecordIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    total = (await session.execute(select(func.count()).select_from(MedicalRecord).where(MedicalRecord.user_id == user_id))).scalar_one()
    if total >= service.MAX_RECORDS:
        raise HTTPException(status.HTTP_409_CONFLICT, "Rekam medis sudah mencapai batas. Hapus yang tidak diperlukan dulu.")
    row = await service.create(session, user_id, kind=body.kind, title=body.title, recorded_on=body.recorded_on,
                               provider=body.provider, details=body.details,
                               values=[v.model_dump(exclude_none=True) for v in body.values])
    return service.record_out(row)


@router.patch("/{record_id}")
async def update_record(
    record_id: uuid.UUID, body: RecordPatch, user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    row = await service.get_owned(session, user_id, record_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Rekam medis tidak ditemukan")
    sent = body.model_fields_set
    if "kind" in sent and body.kind:
        row.kind = body.kind
    if "title" in sent and body.title:
        row.title = body.title.strip()
    if "recorded_on" in sent and body.recorded_on:
        row.recorded_on = service.clean_date(body.recorded_on)
    if "provider" in sent:
        row.provider = (body.provider or "").strip() or None
    if "details" in sent:
        row.details = (body.details or "").strip() or None
    if "values" in sent:
        row.values = [v.model_dump(exclude_none=True) for v in body.values or []] or None
    from sqlalchemy import func as sa_func
    row.updated_at = sa_func.now()
    await session.commit()
    await session.refresh(row)
    return service.record_out(row)


@router.delete("/{record_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_record(
    record_id: uuid.UUID, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> None:
    row = await service.get_owned(session, user_id, record_id)
    if row is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Rekam medis tidak ditemukan")
    await session.delete(row)
    await session.commit()
