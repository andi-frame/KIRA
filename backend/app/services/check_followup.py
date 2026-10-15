"""Menutup lingkaran "Saatnya cek": beberapa hari setelah rekomendasi, KIRA bertanya sudahkah dicek.

Nadanya bertanya, bukan menagih: paling banyak dua tindak lanjut per rekomendasi, berjarak beberapa hari, dan pengguna
selalu bisa menunda atau menyatakan tidak perlu. Semua angka waktu di bawah adalah keputusan produk KIRA, bukan angka klinis.
"""
import uuid
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import CheckRecommendation
from app.models.whatsapp import WaLink, WaOutbox
from app.timeutil import utcnow

FOLLOW_UP_AFTER = timedelta(days=3)  # sejak rekomendasi muncul
FOLLOW_UP_GAP = timedelta(days=4)  # antar tindak lanjut lewat WhatsApp
MAX_FOLLOW_UPS = 2
SNOOZE_FOR = timedelta(days=3)
HOLD_AFTER_DONE = timedelta(days=14)  # "sudah dicek" tapi hasil belum dimasukkan: tanya lagi nanti
HOLD_AFTER_DISMISS = timedelta(days=30)

ACTIONS = ("done", "snooze", "dismiss")
_TEST_NAME = {"fasting_glucose": "gula darah puasa", "blood_pressure": "tensi"}
_EXAMPLE = {"fasting_glucose": "gula puasa 98", "blood_pressure": "tensi 120/80"}


def age_days(row: CheckRecommendation, now: datetime | None = None) -> int:
    return max(0, ((now or utcnow()) - row.created_at).days)


def follow_up_due(row: CheckRecommendation, now: datetime | None = None) -> bool:
    """Saatnya bertanya 'sudah dicek?': masih terbuka, cukup lama, dan tidak sedang ditunda."""
    now = now or utcnow()
    if row.status != "open" or now - row.created_at < FOLLOW_UP_AFTER:
        return False
    return row.snoozed_until is None or row.snoozed_until <= now


def is_held(rows: list[CheckRecommendation], test_kind: str, now: datetime | None = None) -> bool:
    """Ada rekomendasi sejenis yang baru dijawab (sudah dicek / tidak perlu) dan masih dalam masa tahan."""
    now = now or utcnow()
    return any(
        r.test_kind == test_kind and r.status in {"done", "dismissed"} and r.snoozed_until and r.snoozed_until > now
        for r in rows
    )


async def held_rows(session: AsyncSession, user_id: uuid.UUID) -> list[CheckRecommendation]:
    stmt = select(CheckRecommendation).where(
        CheckRecommendation.user_id == user_id,
        CheckRecommendation.status.in_(("done", "dismissed")),
        CheckRecommendation.snoozed_until > utcnow(),
    )
    return list((await session.execute(stmt)).scalars().all())


async def respond(session: AsyncSession, user_id: uuid.UUID, rec_id: uuid.UUID, action: str) -> dict | None:
    """Jawaban pengguna atas tindak lanjut. None bila rekomendasinya tidak ada, bukan miliknya, atau sudah tidak terbuka."""
    row = await session.get(CheckRecommendation, rec_id)
    if row is None or row.user_id != user_id or row.status != "open":
        return None
    now = utcnow()
    if action == "done":
        row.status, row.snoozed_until = "done", now + HOLD_AFTER_DONE
    elif action == "dismiss":
        row.status, row.snoozed_until = "dismissed", now + HOLD_AFTER_DISMISS
    elif action == "snooze":
        row.snoozed_until = now + SNOOZE_FOR
    else:
        raise ValueError(action)
    await session.commit()
    return {
        "status": row.status,
        "snoozed_until": row.snoozed_until.isoformat() if row.snoozed_until else None,
        # Sudah dicek tapi hasilnya belum ada di KIRA: aplikasi menawarkan memasukkannya sekarang.
        "result_needed": action == "done",
        "test_kind": row.test_kind,
    }


def followup_text(test_kind: str, attempt: int) -> str:
    name, example = _TEST_NAME.get(test_kind, "pemeriksaan"), _EXAMPLE.get(test_kind, "")
    send = f" Kalau sudah, kirim saja hasilnya ke sini, misalnya '{example}', nanti proyeksimu kuperbarui." if example else ""
    if attempt == 0:
        return f"Beberapa hari lalu KIRA menyarankan cek {name}. Sudah sempat?{send} Kalau belum, tidak apa-apa."
    return (
        f"Sekadar mengingatkan sekali lagi soal cek {name}, ya.{send} "
        "Kalau tidak jadi atau tidak perlu, abaikan saja pesan ini."
    )


async def enqueue_followups(session: AsyncSession) -> int:
    """Antrikan tindak lanjut lewat WhatsApp untuk rekomendasi terbuka yang sudah waktunya. Mengembalikan jumlahnya."""
    now = utcnow()
    rows = (
        await session.execute(
            select(CheckRecommendation).where(
                CheckRecommendation.status == "open", CheckRecommendation.followups_sent < MAX_FOLLOW_UPS
            )
        )
    ).scalars().all()
    queued = 0
    for row in rows:
        if not follow_up_due(row, now):
            continue
        if row.last_followup_at is not None and now - row.last_followup_at < FOLLOW_UP_GAP:
            continue
        link = (await session.execute(select(WaLink).where(WaLink.user_id == row.user_id))).scalar_one_or_none()
        if link is None:
            continue
        session.add(
            WaOutbox(
                jid=link.jid,
                user_id=row.user_id,
                kind="followup",
                ref=f"{row.id}:{row.followups_sent}",
                text=followup_text(row.test_kind, row.followups_sent),
            )
        )
        row.followups_sent += 1
        row.last_followup_at = now
        queued += 1
    await session.commit()
    return queued
