"""Rekam medis yang dicatat pengguna sendiri, lewat formulir atau cerita di chat.

KIRA hanya menyimpan dan menampilkan ulang apa yang diberikan pengguna. Tidak ada penilaian, diagnosis, atau saran obat dari
catatan ini; obat yang tercatat hanyalah catatan "sedang dipakai", bukan anjuran.
"""
import uuid
from datetime import date

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import MedicalRecord
from app.models.records import RECORD_KINDS
from app.schemas.extraction import MedicalRecordExtract
from app.timeutil import local_date, utcnow

KIND_LABELS = {
    "diagnosis": "Diagnosis", "lab": "Hasil laboratorium", "medication": "Obat yang dipakai", "allergy": "Alergi",
    "procedure": "Tindakan/operasi", "vaccination": "Vaksinasi", "imaging": "Radiologi/pemeriksaan penunjang",
    "visit": "Kunjungan/konsultasi", "other": "Lainnya",
}
MAX_RECORDS = 500


def record_out(r: MedicalRecord) -> dict:
    return {"id": str(r.id), "kind": r.kind, "kind_label": KIND_LABELS.get(r.kind, r.kind), "title": r.title,
            "recorded_on": r.recorded_on.isoformat(), "provider": r.provider, "details": r.details,
            "values": r.values or [], "source": r.source, "created_at": r.created_at.isoformat()}


async def list_records(session: AsyncSession, user_id: uuid.UUID, kind: str | None = None) -> list[MedicalRecord]:
    stmt = select(MedicalRecord).where(MedicalRecord.user_id == user_id)
    if kind:
        stmt = stmt.where(MedicalRecord.kind == kind)
    stmt = stmt.order_by(MedicalRecord.recorded_on.desc(), MedicalRecord.created_at.desc()).limit(MAX_RECORDS)
    return list((await session.execute(stmt)).scalars().all())


async def get_owned(session: AsyncSession, user_id: uuid.UUID, record_id: uuid.UUID) -> MedicalRecord | None:
    r = await session.get(MedicalRecord, record_id)
    return r if r is not None and r.user_id == user_id else None


def clean_date(value: date | str | None) -> date:
    """Tanggal catatan: yang disebut pengguna, tetapi tidak di masa depan; kosong = hari ini."""
    today = local_date(utcnow())
    if isinstance(value, str):
        try:
            value = date.fromisoformat(value)
        except ValueError:
            value = None
    return min(value, today) if value else today


def clean_kind(kind: str) -> str:
    return kind if kind in RECORD_KINDS else "other"


async def create(session: AsyncSession, user_id: uuid.UUID, *, kind: str, title: str, recorded_on: date | str | None = None,
                 provider: str | None = None, details: str | None = None, values: list[dict] | None = None,
                 source: str = "manual", commit: bool = True) -> MedicalRecord:
    row = MedicalRecord(user_id=user_id, kind=clean_kind(kind), title=title.strip(), recorded_on=clean_date(recorded_on),
                        provider=(provider or "").strip() or None, details=(details or "").strip() or None,
                        values=values or None, source=source)
    session.add(row)
    await session.flush()
    if commit:
        await session.commit()
    return row


async def add_from_chat(session: AsyncSession, user_id: uuid.UUID, e: MedicalRecordExtract) -> str:
    """Simpan rekam medis dari cerita pengguna. Mengembalikan kalimat untuk CATATAN SISTEM."""
    row = await create(
        session, user_id, kind=e.kind, title=e.title, recorded_on=e.recorded_on, provider=e.provider, details=e.details,
        values=[v.model_dump(exclude_none=True) for v in e.values] or None, source="chat", commit=False,
    )
    return (f"Rekam medis TERSIMPAN: {KIND_LABELS[row.kind]} '{row.title}' tanggal {row.recorded_on.isoformat()}. "
            "Konfirmasi singkat jenis dan tanggalnya, katakan bisa dilihat/diubah di Profil > Rekam medis. "
            "Jangan menilai isinya, jangan mendiagnosis, jangan menyarankan obat atau dosis.")
