"""Hak pemilik data: persetujuan, unduh semua data, dan hapus akun beserta seluruh isinya (UU PDP No. 27/2022)."""
import uuid
from datetime import date, datetime
from decimal import Decimal

from sqlalchemy import delete, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    CheckRecommendation,
    ClinicalResult,
    Diagnosis,
    FamilyLink,
    HealthProfile,
    Log,
    LogItem,
    Message,
    RiskSnapshot,
    User,
    WaLink,
    WeeklySummary,
)
from app.timeutil import utcnow

# Naikkan bila teks persetujuan berubah; akun dengan versi lama diminta menyetujui ulang.
CONSENT_VERSION = "2026-10"
EXPORT_FORMAT = 1

# Kolom yang tidak ikut diunduh: rahasia akun, bukan data pemilik.
_HIDDEN = {"pin_hash"}


def _plain(value):
    if isinstance(value, uuid.UUID):
        return str(value)
    if isinstance(value, (datetime, date)):
        return value.isoformat()
    if isinstance(value, Decimal):
        return float(value)
    return value


def _row(obj) -> dict:
    return {c.name: _plain(getattr(obj, c.name)) for c in obj.__table__.columns if c.name not in _HIDDEN}


async def _rows(session: AsyncSession, model, *conditions, order=None) -> list[dict]:
    stmt = select(model).where(*conditions)
    if order is not None:
        stmt = stmt.order_by(order)
    return [_row(r) for r in (await session.execute(stmt)).scalars().all()]


async def record_consent(session: AsyncSession, user_id: uuid.UUID, *, commit: bool = True) -> datetime:
    user = await session.get(User, user_id)
    user.consented_at, user.consent_version = utcnow(), CONSENT_VERSION
    if commit:
        await session.commit()
    return user.consented_at


def has_current_consent(user: User) -> bool:
    return user.consented_at is not None and user.consent_version == CONSENT_VERSION


async def export_account(session: AsyncSession, user_id: uuid.UUID) -> dict:
    """Salinan lengkap data pemilik dalam JSON yang bisa dibaca manusia dan mesin."""
    user = await session.get(User, user_id)
    profile = await session.get(HealthProfile, user_id)
    logs = await _rows(session, Log, Log.user_id == user_id, order=Log.occurred_at)
    items = await _rows(
        session, LogItem, LogItem.log_id.in_(select(Log.id).where(Log.user_id == user_id))
    )
    by_log: dict[str, list[dict]] = {}
    for item in items:
        by_log.setdefault(item["log_id"], []).append(item)
    for log in logs:
        log["items"] = by_log.get(log["id"], [])
    wa = await session.execute(select(WaLink).where(WaLink.user_id == user_id))
    return {
        "format": EXPORT_FORMAT,
        "exported_at": utcnow().isoformat(),
        "note": "Salinan data KIRA milikmu. PIN tidak disertakan.",
        "account": _row(user),
        "profile": _row(profile) if profile else None,
        "diagnoses": await _rows(session, Diagnosis, Diagnosis.user_id == user_id),
        "logs": logs,
        "clinical_results": await _rows(
            session, ClinicalResult, ClinicalResult.user_id == user_id, order=ClinicalResult.measured_at
        ),
        "risk_snapshots": await _rows(session, RiskSnapshot, RiskSnapshot.user_id == user_id),
        "check_recommendations": await _rows(session, CheckRecommendation, CheckRecommendation.user_id == user_id),
        "weekly_summaries": await _rows(session, WeeklySummary, WeeklySummary.user_id == user_id),
        "messages": await _rows(session, Message, Message.user_id == user_id, order=Message.created_at),
        "family_links": await _rows(
            session, FamilyLink, or_(FamilyLink.owner_id == user_id, FamilyLink.member_id == user_id)
        ),
        "whatsapp_linked": wa.scalar_one_or_none() is not None,
    }


async def delete_account(session: AsyncSession, user_id: uuid.UUID) -> None:
    """Menghapus akun; semua tabel anak ikut terhapus lewat ON DELETE CASCADE."""
    user = await session.get(User, user_id)
    # Undangan yang belum diterima hanya menyimpan nomor (member_id kosong), jadi tidak ikut cascade.
    await session.execute(delete(FamilyLink).where(FamilyLink.member_phone == user.phone))
    await session.delete(user)
    await session.commit()
