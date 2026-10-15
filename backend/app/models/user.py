import uuid
from datetime import date, datetime

from sqlalchemy import Boolean, Date, DateTime, ForeignKey, Index, Numeric, Text, func, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, created_at, uuid_pk

FLOAT = Numeric(asdecimal=False)


class User(Base):
    __tablename__ = "users"
    # Nama pengguna unik tanpa membedakan huruf besar/kecil. Boleh kosong hanya untuk akun lama; akun baru wajib punya.
    __table_args__ = (Index("ux_users_username_lower", func.lower(text("username")), unique=True),)
    id: Mapped[uuid.UUID] = uuid_pk()
    username: Mapped[str | None] = mapped_column(Text)
    # Nomor tetap wajib: dipakai untuk tautan WhatsApp dan undangan keluarga.
    phone: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    pin_hash: Mapped[str] = mapped_column(Text, nullable=False)
    display_name: Mapped[str | None] = mapped_column(Text)
    mode: Mapped[str] = mapped_column(Text, nullable=False, server_default="prevention")
    created_at: Mapped[datetime] = created_at()


class HealthProfile(Base):
    __tablename__ = "health_profiles"
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    birth_date: Mapped[date | None] = mapped_column(Date)
    sex: Mapped[str | None] = mapped_column(Text)
    height_cm: Mapped[float | None] = mapped_column(FLOAT)
    weight_kg: Mapped[float | None] = mapped_column(FLOAT)
    waist_cm: Mapped[float | None] = mapped_column(FLOAT)
    family_history_diabetes: Mapped[str | None] = mapped_column(Text)
    parent_hypertension: Mapped[bool | None] = mapped_column(Boolean)
    smoker: Mapped[bool | None] = mapped_column(Boolean)
    on_bp_medication: Mapped[bool | None] = mapped_column(Boolean)
    history_high_glucose: Mapped[bool | None] = mapped_column(Boolean)
    # baseline dari onboarding, dipakai sebelum ada cukup log 14 hari
    usual_active_30min: Mapped[bool | None] = mapped_column(Boolean)
    usual_veg_fruit: Mapped[bool | None] = mapped_column(Boolean)
    food_preferences: Mapped[dict] = mapped_column(JSONB, nullable=False, server_default=text("'{}'::jsonb"))
    updated_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


class Diagnosis(Base):
    __tablename__ = "diagnoses"
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    condition: Mapped[str] = mapped_column(Text, nullable=False)  # diabetes | prediabetes | hypertension
    diagnosed_at: Mapped[date | None] = mapped_column(Date)
    confirmed_by: Mapped[str | None] = mapped_column(Text)
