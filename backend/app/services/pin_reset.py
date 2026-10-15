"""Atur ulang PIN lewat kode sekali pakai yang dikirim ke WhatsApp yang sudah tertaut ke akun.

Hanya nomor yang sudah tertaut yang bisa menerima kode: KIRA tidak punya jalur lain yang terbukti milik pemilik akun.
Jawaban permintaan kode sama untuk akun yang ada maupun tidak, agar tidak bisa dipakai menebak siapa yang terdaftar.
"""
import hashlib
import hmac
import secrets
import uuid
from datetime import timedelta

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.models import PinResetCode, User
from app.models.whatsapp import WaLink, WaOutbox
from app.repos import sessions
from app.security import hash_pin
from app.timeutil import utcnow

CODE_TTL = timedelta(minutes=10)
MAX_ATTEMPTS = 5
RESEND_AFTER = timedelta(seconds=60)
OTP_KIND = "otp"
SENT_PLACEHOLDER = "[kode atur ulang PIN sudah dikirim]"
REQUEST_REPLY = "Kalau akun ini punya WhatsApp yang tertaut, kode 6 angka sudah dikirim ke sana. Berlaku 10 menit."


def _digest(user_id: uuid.UUID, code: str) -> str:
    # Diikat ke akun dan rahasia server supaya hash kode yang bocor tidak bisa dicocokkan di tempat lain.
    return hmac.new(settings.jwt_secret.encode(), f"{user_id}:{code}".encode(), hashlib.sha256).hexdigest()


def _new_code() -> str:
    return f"{secrets.randbelow(1_000_000):06d}"


async def request_code(session: AsyncSession, user: User | None) -> bool:
    """True bila kode benar-benar masuk antrean WhatsApp. Pemanggil tidak boleh membocorkan nilai ini."""
    if user is None:
        return False
    link = (await session.execute(select(WaLink).where(WaLink.user_id == user.id))).scalar_one_or_none()
    if link is None:
        return False
    existing = await session.get(PinResetCode, user.id)
    if existing is not None and utcnow() - existing.created_at < RESEND_AFTER:
        return False  # tahan permintaan beruntun, kode sebelumnya masih berlaku
    code = _new_code()
    await session.execute(delete(PinResetCode).where(PinResetCode.user_id == user.id))
    session.add(PinResetCode(user_id=user.id, code_hash=_digest(user.id, code), expires_at=utcnow() + CODE_TTL))
    session.add(
        WaOutbox(
            jid=link.jid,
            user_id=user.id,
            kind=OTP_KIND,
            text=f"Kode atur ulang PIN KIRA: {code}. Berlaku 10 menit. "
            "Jangan bagikan ke siapa pun. Abaikan pesan ini bila bukan kamu yang meminta.",
        )
    )
    await session.commit()
    return True


async def confirm(session: AsyncSession, user: User | None, code: str, new_pin: str) -> str:
    """Mengatur ulang PIN. Hasil: 'ok', 'invalid' (kode salah atau kedaluwarsa), atau 'locked' (terlalu banyak salah)."""
    if user is None:
        return "invalid"
    row = await session.get(PinResetCode, user.id)
    if row is None or row.expires_at < utcnow():
        return "invalid"
    if row.attempts >= MAX_ATTEMPTS:
        return "locked"
    if not hmac.compare_digest(row.code_hash, _digest(user.id, code)):
        row.attempts += 1
        await session.commit()
        return "locked" if row.attempts >= MAX_ATTEMPTS else "invalid"
    user.pin_hash = hash_pin(new_pin)
    await session.delete(row)
    # PIN baru berarti semua perangkat lama harus masuk lagi: pihak yang tahu PIN lama tidak boleh tetap masuk.
    await sessions.revoke_all(session, user.id, commit=False)
    await session.commit()
    return "ok"
