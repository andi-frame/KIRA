import uuid
from datetime import date, datetime

from sqlalchemy import ARRAY, Date, DateTime, ForeignKey, Integer, SmallInteger, Text, func, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base


class PlanPreference(Base):
    """Preferensi rencana harian: jam, hari olahraga, tujuan, kanal pengingat, jam tenang."""

    __tablename__ = "plan_preferences"
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    wake_time: Mapped[str] = mapped_column(Text, nullable=False, server_default="06:00")
    meal_times: Mapped[dict] = mapped_column(JSONB, nullable=False, server_default=text("'{}'::jsonb"))
    exercise_time: Mapped[str] = mapped_column(Text, nullable=False, server_default="17:00")
    exercise_days: Mapped[list[int]] = mapped_column(ARRAY(SmallInteger), nullable=False, server_default=text("'{0,1,2,3,4}'"))
    exercise_kinds: Mapped[list[str]] = mapped_column(ARRAY(Text), nullable=False, server_default=text("'{jalan cepat}'"))
    strength_days: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    goal: Mapped[str] = mapped_column(Text, nullable=False, server_default="jaga")
    channels: Mapped[dict] = mapped_column(JSONB, nullable=False, server_default=text('\'{"app": true, "whatsapp": false}\'::jsonb'))
    reminders: Mapped[dict] = mapped_column(JSONB, nullable=False, server_default=text("'{}'::jsonb"))
    quiet_hours: Mapped[dict] = mapped_column(JSONB, nullable=False, server_default=text('\'{"start": "21:30", "end": "06:00"}\'::jsonb'))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class PlanOverride(Base):
    __tablename__ = "plan_overrides"
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    date: Mapped[date] = mapped_column(Date, primary_key=True)
    slot: Mapped[str] = mapped_column(Text, primary_key=True)
    replacement: Mapped[dict] = mapped_column(JSONB, nullable=False)
