import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, Float, ForeignKey, Integer, Text, func
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


class Faskes(Base):
    __tablename__ = "faskes"
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    kind: Mapped[str] = mapped_column(Text, nullable=False)  # posyandu | puskesmas
    lat: Mapped[float] = mapped_column(Float, nullable=False)
    lng: Mapped[float] = mapped_column(Float, nullable=False)
    address: Mapped[str | None] = mapped_column(Text)
