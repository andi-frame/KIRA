import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, created_at, uuid_pk


class WaLink(Base):
    """Nomor WhatsApp yang sudah ditautkan ke satu akun (satu nomor = satu akun)."""

    __tablename__ = "wa_links"
    jid: Mapped[str] = mapped_column(Text, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), unique=True, nullable=False
    )
    created_at: Mapped[datetime] = created_at()


class WaLinkCode(Base):
    """Kode sekali pakai ("KIRA 4821") yang dibuat di aplikasi dan dikirim dari WhatsApp."""

    __tablename__ = "wa_link_codes"
    code: Mapped[str] = mapped_column(Text, primary_key=True)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)


class WaOutbox(Base):
    """Pesan keluar yang diambil bot (pengingat check-in, ajakan dari keluarga)."""

    __tablename__ = "wa_outbox"
    id: Mapped[uuid.UUID] = uuid_pk()
    jid: Mapped[str] = mapped_column(Text, nullable=False)
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    kind: Mapped[str] = mapped_column(Text, nullable=False)  # reminder | family
    text: Mapped[str] = mapped_column(Text, nullable=False)
    created_at: Mapped[datetime] = created_at()
    sent_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))

