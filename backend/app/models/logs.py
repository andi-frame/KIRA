import uuid
from datetime import datetime

from sqlalchemy import ARRAY, Boolean, DateTime, ForeignKey, Index, Text, func, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, uuid_pk
from app.models.user import FLOAT


class Food(Base):
    __tablename__ = "foods"
    id: Mapped[str] = mapped_column(Text, primary_key=True)
    name: Mapped[str] = mapped_column(Text, nullable=False)
    aliases: Mapped[list[str]] = mapped_column(ARRAY(Text), nullable=False, server_default=text("'{}'"))
    per100g: Mapped[dict] = mapped_column(JSONB, nullable=False)
    default_portion_g: Mapped[float | None] = mapped_column(FLOAT)
    tkpi_code: Mapped[str | None] = mapped_column(Text)  # padanan di TKPI Kemenkes 2017, bila ada
    source_note: Mapped[str | None] = mapped_column(Text)  # asal tiap nilai (TKPI atau estimasi)


class Log(Base):
    __tablename__ = "logs"
    __table_args__ = (Index("ix_logs_user_occurred", "user_id", text("occurred_at DESC")),)
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    occurred_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    kind: Mapped[str] = mapped_column(Text, nullable=False)  # meal | drink | sleep | activity
    source: Mapped[str] = mapped_column(Text, nullable=False)  # text | voice | photo_food | photo_receipt
    raw_text: Mapped[str | None] = mapped_column(Text)
    extracted: Mapped[dict] = mapped_column(JSONB, nullable=False)
    corrected: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("false"))


class LogItem(Base):
    __tablename__ = "log_items"
    id: Mapped[uuid.UUID] = uuid_pk()
    log_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("logs.id", ondelete="CASCADE"), nullable=False
    )
    food_id: Mapped[str | None] = mapped_column(Text, ForeignKey("foods.id"))
    name: Mapped[str] = mapped_column(Text, nullable=False)
    portion_g: Mapped[float | None] = mapped_column(FLOAT)
    sugar_g: Mapped[float | None] = mapped_column(FLOAT)
    sodium_mg: Mapped[float | None] = mapped_column(FLOAT)
    fat_g: Mapped[float | None] = mapped_column(FLOAT)
    kcal: Mapped[float | None] = mapped_column(FLOAT)


class Product(Base):
    """Cache hasil Open Food Facts per kode batang (basis data luar membatasi 15 permintaan/menit per IP)."""

    __tablename__ = "products"
    barcode: Mapped[str] = mapped_column(Text, primary_key=True)
    found: Mapped[bool] = mapped_column(Boolean, nullable=False)
    name: Mapped[str | None] = mapped_column(Text)
    brand: Mapped[str | None] = mapped_column(Text)
    serving_g: Mapped[float | None] = mapped_column(FLOAT)
    is_drink: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default=text("false"))
    per100g: Mapped[dict] = mapped_column(JSONB, nullable=False, server_default=text("'{}'::jsonb"))
    fetched_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())
