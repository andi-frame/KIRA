import random
import re
import uuid
from datetime import timedelta

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User
from app.models.whatsapp import WaLink, WaLinkCode
from app.timeutil import utcnow

CODE_TTL = timedelta(minutes=15)
MAX_REPLY_SENTENCES = 4
MAX_REPLY_CHARS = 900
_LINK_PATTERN = re.compile(r"^\s*kira\s+(\d{4})\s*$", re.IGNORECASE)

NOT_LINKED_REPLY = (
    "Nomor ini belum tertaut ke akun KIRA. Buka aplikasi KIRA, masuk ke Profil lalu Tautkan WhatsApp, "
    "kemudian kirim kode seperti 'KIRA 1234' ke sini."
)
BAD_CODE_REPLY = "Kodenya tidak valid atau sudah kedaluwarsa, jadi nomor ini belum tertaut. Buat kode baru di aplikasi ya."
EMPTY_REPLY = "Kirim teks, voice note, atau foto makananmu ya."


def parse_link_code(text: str | None) -> str | None:
    match = _LINK_PATTERN.match(text or "")
    return match.group(1) if match else None


def shorten(reply: str) -> str:
    """Balasan WhatsApp singkat: maksimal 4 kalimat dan 900 karakter."""
    sentences = re.split(r"(?<=[.!?])\s+", reply.strip())
    short = " ".join(sentences[:MAX_REPLY_SENTENCES])
    return short if len(short) <= MAX_REPLY_CHARS else short[: MAX_REPLY_CHARS - 1].rstrip() + "…"


def photo_kind(caption: str | None) -> str:
    lowered = (caption or "").lower()
    if "struk" in lowered or "nota" in lowered:
        return "receipt"
    # "label" memuat "lab": periksa dulu sebelum kata kunci hasil pemeriksaan.
    if any(w in lowered for w in ("label", "kemasan", "info gizi", "nilai gizi")):
        return "label"
    if any(w in lowered for w in ("hasil", "lab", "tensi", "tensimeter", "ckg")):
        return "result"
    return "food"


async def create_link_code(session: AsyncSession, user_id: uuid.UUID) -> str:
    await session.execute(delete(WaLinkCode).where(WaLinkCode.expires_at < utcnow()))
    await session.execute(delete(WaLinkCode).where(WaLinkCode.user_id == user_id))
    active = set((await session.execute(select(WaLinkCode.code))).scalars().all())
    code = next(c for c in (f"{random.randint(0, 9999):04d}" for _ in range(200)) if c not in active)
    session.add(WaLinkCode(code=code, user_id=user_id, expires_at=utcnow() + CODE_TTL))
    await session.commit()
    return f"KIRA {code}"


async def redeem_link_code(session: AsyncSession, code: str, jid: str) -> User | None:
    row = await session.get(WaLinkCode, code)
    if row is None or row.expires_at < utcnow():
        return None
    user = await session.get(User, row.user_id)
    await session.execute(delete(WaLink).where((WaLink.jid == jid) | (WaLink.user_id == row.user_id)))
    session.add(WaLink(jid=jid, user_id=row.user_id))
    await session.delete(row)
    await session.commit()
    return user


async def linked_user_id(session: AsyncSession, jid: str) -> uuid.UUID | None:
    link = await session.get(WaLink, jid)
    return link.user_id if link else None
