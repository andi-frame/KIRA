import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, Float, ForeignKey, Integer, Text, UniqueConstraint, func
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, created_at, uuid_pk


def _user_fk() -> Mapped[uuid.UUID]:
    return mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)


class ClinicalResult(Base):
    __tablename__ = "clinical_results"
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = _user_fk()
    # fasting_glucose | random_glucose | blood_pressure | hba1c | waist
    kind: Mapped[str] = mapped_column(Text, nullable=False)
    value: Mapped[dict] = mapped_column(JSONB, nullable=False)  # BP: {"sys":135,"dia":85}
    measured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    source: Mapped[str] = mapped_column(Text, nullable=False)  # ckg | lab | self


class RiskSnapshot(Base):
    __tablename__ = "risk_snapshots"
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = _user_fk()
    model: Mapped[str] = mapped_column(Text, nullable=False)  # findrisc | bp_category
    score_low: Mapped[int | None] = mapped_column(Integer)
    score_high: Mapped[int | None] = mapped_column(Integer)
    category_low: Mapped[str | None] = mapped_column(Text)
    category_high: Mapped[str | None] = mapped_column(Text)
    inputs: Mapped[dict] = mapped_column(JSONB, nullable=False)
    computed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class CheckRecommendation(Base):
    __tablename__ = "check_recommendations"
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = _user_fk()
    test_kind: Mapped[str] = mapped_column(Text, nullable=False)
    reason: Mapped[str] = mapped_column(Text, nullable=False)
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="open")  # open | done | dismissed
    created_at: Mapped[datetime] = created_at()
    # Sampai kapan tindak lanjut ditunda (open) atau rekomendasi sejenis ditahan (done/dismissed).
    snoozed_until: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    followups_sent: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    last_followup_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class WeeklySummary(Base):
    __tablename__ = "weekly_summaries"
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    week_start: Mapped[date] = mapped_column(Date, primary_key=True)
    metrics: Mapped[dict | None] = mapped_column(JSONB)
    summary_text: Mapped[str | None] = mapped_column(Text)


class Message(Base):
    __tablename__ = "messages"
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = _user_fk()
    role: Mapped[str] = mapped_column(Text, nullable=False)  # user | assistant | tool
    content: Mapped[str | None] = mapped_column(Text)
    tool_calls: Mapped[list | None] = mapped_column(JSONB)
    channel: Mapped[str] = mapped_column(Text, nullable=False)  # app | whatsapp
    created_at: Mapped[datetime] = created_at()
    # Untuk memulihkan obrolan di aplikasi: {"log_ids": [...], "red_flag": ...}. Tidak berisi angka kesehatan.
    meta: Mapped[dict | None] = mapped_column(JSONB)


class Faskes(Base):
    __tablename__ = "faskes"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    kind: Mapped[str] = mapped_column(Text, nullable=False)  # posyandu | puskesmas
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lng: Mapped[float] = mapped_column(Float, nullable=False)
    address: Mapped[str | None] = mapped_column(Text)


class BpProtocol(Base):
    """Satu putaran ukur tensi di rumah selama 7 hari (protokol ESH 2021). Hanya satu yang aktif per pengguna."""

    __tablename__ = "bp_protocols"
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = _user_fk()
    started_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="active")  # active | completed | cancelled
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    avg_sys: Mapped[float | None] = mapped_column(Float)
    avg_dia: Mapped[float | None] = mapped_column(Float)
    readings_used: Mapped[int | None] = mapped_column(Integer)
    result_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("clinical_results.id", ondelete="SET NULL"))


class BpReading(Base):
    __tablename__ = "bp_readings"
    id: Mapped[uuid.UUID] = uuid_pk()
    protocol_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("bp_protocols.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[uuid.UUID] = _user_fk()
    measured_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    sys: Mapped[int] = mapped_column(Integer, nullable=False)
    dia: Mapped[int] = mapped_column(Integer, nullable=False)
    session: Mapped[str] = mapped_column(Text, nullable=False)  # morning | evening
    pulse: Mapped[int | None] = mapped_column(Integer)  # detak jantung (kali/menit) saat bacaan itu, bila diukur


class WhatIfScenario(Base):
    """Skenario "bagaimana kalau" yang disimpan pengguna, dengan hasil saat disimpan untuk dibandingkan dengan sekarang."""

    __tablename__ = "whatif_scenarios"
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = _user_fk()
    name: Mapped[str] = mapped_column(Text, nullable=False)
    params: Mapped[dict] = mapped_column(JSONB, nullable=False)
    saved_before: Mapped[dict] = mapped_column(JSONB, nullable=False)  # {"low","high"} rentang skor saat disimpan
    saved_after: Mapped[dict] = mapped_column(JSONB, nullable=False)
    created_at: Mapped[datetime] = created_at()


class Goal(Base):
    """Target mingguan pribadi (satu per jenis). Kemajuannya selalu dihitung dari catatan, tidak disimpan."""

    __tablename__ = "goals"
    __table_args__ = (UniqueConstraint("user_id", "kind", name="ux_goals_user_kind"),)
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = _user_fk()
    kind: Mapped[str] = mapped_column(Text, nullable=False)
    target: Mapped[float] = mapped_column(Float, nullable=False)
    created_at: Mapped[datetime] = created_at()
