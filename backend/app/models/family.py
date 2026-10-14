import uuid
from datetime import datetime

from sqlalchemy import ForeignKey, Text, text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, created_at, uuid_pk


class FamilyLink(Base):
    """Undangan keluarga dari pemilik data ke nomor tertentu. Anggota hanya melihat ringkasan yang diizinkan."""

    __tablename__ = "family_links"
    id: Mapped[uuid.UUID] = uuid_pk()
    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    member_phone: Mapped[str] = mapped_column(Text, nullable=False)
    member_id: Mapped[uuid.UUID | None] = mapped_column(UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"))
    permissions: Mapped[dict] = mapped_column(
        JSONB,
        nullable=False,
        server_default=text('\'{"checkin_status": true, "check_reminders": true}\'::jsonb'),
    )
    status: Mapped[str] = mapped_column(Text, nullable=False, server_default="pending")  # pending | active
    created_at: Mapped[datetime] = created_at()
