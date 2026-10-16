import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, Index, Text, func, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, created_at, uuid_pk

RECORD_KINDS = ("diagnosis", "lab", "medication", "allergy", "procedure", "vaccination", "imaging", "visit", "other")


class MedicalRecord(Base):
    """Rekam medis yang dicatat pengguna sendiri (diagnosis, hasil lab, obat yang sedang dipakai, alergi, dst.).

    KIRA hanya menyimpan dan merangkum; tidak menilai, mendiagnosis, atau menyarankan obat."""

    __tablename__ = "medical_records"
    __table_args__ = (Index("ix_medical_records_user_date", "user_id", text("recorded_on DESC")),)
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)
    kind: Mapped[str] = mapped_column(Text, nullable=False)
    title: Mapped[str] = mapped_column(Text, nullable=False)
    recorded_on: Mapped[date] = mapped_column(Date, nullable=False)
    provider: Mapped[str | None] = mapped_column(Text)  # dokter / faskes / laboratorium
    details: Mapped[str | None] = mapped_column(Text)
    values: Mapped[list | None] = mapped_column(JSONB)  # [{"name","value","unit"}] untuk hasil lab
    source: Mapped[str] = mapped_column(Text, nullable=False, server_default="manual")  # manual | chat
    created_at: Mapped[datetime] = created_at()
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
