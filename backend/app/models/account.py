import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Integer, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, created_at, uuid_pk


def _user_fk() -> Mapped[uuid.UUID]:
    return mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False)


class AuthSession(Base):
    """Satu perangkat yang sedang masuk. Hanya hash token penyegar yang disimpan; token itu berputar tiap dipakai."""

    __tablename__ = "auth_sessions"
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = _user_fk()
    token_hash: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    created_at: Mapped[datetime] = created_at()
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    last_used_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class AccessLog(Base):
    """Catatan siapa melihat data pemilik. Pemilik berhak tahu setiap kali ringkasannya dibuka orang lain."""

    __tablename__ = "access_logs"
    id: Mapped[uuid.UUID] = uuid_pk()
    owner_id: Mapped[uuid.UUID] = _user_fk()
    viewer_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"))
    viewer_name: Mapped[str] = mapped_column(Text, nullable=False)  # nama saat itu; tetap terbaca bila akun pelihat dihapus
    kind: Mapped[str] = mapped_column(Text, nullable=False)  # family_status | share_link
    detail: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = created_at()


class ShareLink(Base):
    """Tautan ringkasan untuk dokter yang kedaluwarsa dan bisa dicabut. Token mentah tidak disimpan."""

    __tablename__ = "share_links"
    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = _user_fk()
    token_hash: Mapped[str] = mapped_column(Text, unique=True, nullable=False)
    days: Mapped[int] = mapped_column(Integer, nullable=False)
    created_at: Mapped[datetime] = created_at()
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    open_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    last_opened_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class PinResetCode(Base):
    """Kode sekali pakai untuk mengatur ulang PIN lewat WhatsApp. Hanya hash yang disimpan; satu kode aktif per akun."""

    __tablename__ = "pin_reset_codes"
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    code_hash: Mapped[str] = mapped_column(Text, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    attempts: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    created_at: Mapped[datetime] = created_at()


class IdempotencyKey(Base):
    """Jawaban yang sudah diberikan untuk satu kunci kiriman. Kiriman ulang (mis. dari antrean offline) mendapat jawaban
    yang sama tanpa mencatat dua kali."""

    __tablename__ = "idempotency_keys"
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    key: Mapped[str] = mapped_column(Text, primary_key=True)
    response: Mapped[dict] = mapped_column(JSONB, nullable=False)
    created_at: Mapped[datetime] = created_at()
