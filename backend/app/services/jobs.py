"""Pekerjaan terjadwal (tanpa LLM): ringkasan mingguan dan evaluasi "saatnya cek".

Semua fungsi menerima session dan waktu acuan agar mudah dites; penjadwalnya ada di app/scheduler.py.
"""
import uuid
from collections import defaultdict
from datetime import date, datetime, time, timedelta

from sqlalchemy import func, select
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.habits import weekly_changes  # noqa: F401 - aturan derau mingguan satu sumber (Beranda juga memakainya)
from app.models import FamilyLink, Log, LogItem, User, WeeklySummary
from app.models.whatsapp import WaLink, WaOutbox
from app.services import risk
from app.timeutil import WIB, local_date, start_of_today_utc, utcnow

SWEET_DRINK_MIN_SUGAR_G = risk.SWEET_DRINK_MIN_SUGAR_G
_MONTHS = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"]


def week_bounds(today: date) -> tuple[date, date]:
    """Senin sampai Minggu pada minggu sebelum `today`."""
    this_monday = today - timedelta(days=today.weekday())
    return this_monday - timedelta(days=7), this_monday - timedelta(days=1)


def _fmt(d: date) -> str:
    return f"{d.day} {_MONTHS[d.month - 1]}"


async def _metrics(session: AsyncSession, user_id: uuid.UUID, start: date, end: date) -> dict | None:
    lo = datetime.combine(start, time.min, tzinfo=WIB)
    hi = datetime.combine(end + timedelta(days=1), time.min, tzinfo=WIB)
    logs = (
        await session.execute(select(Log).where(Log.user_id == user_id, Log.occurred_at >= lo, Log.occurred_at < hi))
    ).scalars().all()
    if not logs:
        return None
    items = (
        await session.execute(select(LogItem).where(LogItem.log_id.in_([lg.id for lg in logs])))
    ).scalars().all()
    by_log: dict[uuid.UUID, list[LogItem]] = defaultdict(list)
    for item in items:
        by_log[item.log_id].append(item)

    days = {local_date(lg.occurred_at) for lg in logs}
    sweet_count = sugar_total = activity_min = 0.0
    sleep_hours: list[float] = []
    for lg in logs:
        sugar = sum(float(i.sugar_g or 0) for i in by_log[lg.id])
        sugar_total += sugar
        if lg.kind == "drink":
            count = float(lg.extracted.get("count", 1) or 1)
            if sugar / count >= SWEET_DRINK_MIN_SUGAR_G:
                sweet_count += count
        elif lg.kind == "sleep" and lg.extracted.get("hours"):
            sleep_hours.append(float(lg.extracted["hours"]))
        elif lg.kind == "activity":
            activity_min += float(lg.extracted.get("minutes", 0) or 0)
    n = len(days)
    return {
        "days_logged": n,
        "sweet_drinks_per_day": round(sweet_count / n, 2),
        "sugar_g_per_day": round(sugar_total / n, 1),
        "sleep_hours_avg": round(sum(sleep_hours) / len(sleep_hours), 1) if sleep_hours else None,
        "active_minutes_per_day": round(activity_min / n, 1),
    }


def _summary_text(start: date, end: date, m: dict) -> str:
    parts = [
        f"Minggu {_fmt(start)} sampai {_fmt(end)}: tercatat {m['days_logged']} hari",
        f"rata-rata gula dari makan dan minum {m['sugar_g_per_day']:g} g per hari",
        f"minuman manis {m['sweet_drinks_per_day']:g} per hari",
        f"aktif {m['active_minutes_per_day']:g} menit per hari",
    ]
    if m["sleep_hours_avg"] is not None:
        parts.append(f"tidur rata-rata {m['sleep_hours_avg']:g} jam")
    return "; ".join(parts) + "."


async def build_weekly_summaries(session: AsyncSession, today: date | None = None) -> int:
    """Buat/perbarui ringkasan minggu lalu untuk setiap pengguna yang punya log. Mengembalikan jumlahnya."""
    start, end = week_bounds(today or local_date(utcnow()))
    user_ids = (await session.execute(select(User.id))).scalars().all()
    written = 0
    for uid in user_ids:
        metrics = await _metrics(session, uid, start, end)
        if metrics is None:
            continue
        stmt = insert(WeeklySummary).values(
            user_id=uid, week_start=start, metrics=metrics, summary_text=_summary_text(start, end, metrics)
        )
        await session.execute(
            stmt.on_conflict_do_update(
                index_elements=["user_id", "week_start"],
                set_={"metrics": stmt.excluded.metrics, "summary_text": stmt.excluded.summary_text},
            )
        )
        written += 1
    await session.commit()
    return written


async def evaluate_checks_for_all(session: AsyncSession) -> int:
    """Evaluasi pemicu 'saatnya cek' untuk semua pengguna (job malam hari)."""
    user_ids = (await session.execute(select(User.id))).scalars().all()
    for uid in user_ids:
        await risk.refresh_check_recommendation(session, uid)
    return len(user_ids)


async def enqueue_reminders(session: AsyncSession) -> int:
    """Pengingat check-in lewat WhatsApp: hanya untuk akun tertaut yang belum mencatat apa pun hari ini,
    dan maksimal satu pengingat per hari."""
    today = start_of_today_utc()
    links = (await session.execute(select(WaLink))).scalars().all()
    queued = 0
    for link in links:
        has_log = (
            await session.execute(
                select(Log.id).where(Log.user_id == link.user_id, Log.occurred_at >= today).limit(1)
            )
        ).first()
        sent_today = (
            await session.execute(
                select(WaOutbox.id)
                .where(WaOutbox.user_id == link.user_id, WaOutbox.kind == "reminder", WaOutbox.created_at >= today)
                .limit(1)
            )
        ).first()
        if has_log or sent_today:
            continue
        user = await session.get(User, link.user_id)
        name = f" {user.display_name}" if user and user.display_name else ""
        session.add(
            WaOutbox(
                jid=link.jid,
                user_id=link.user_id,
                kind="reminder",
                text=f"Hai{name}, sudah check-in hari ini? Ceritakan makan, minum, dan tidurmu, cukup satu menit.",
            )
        )
        queued += 1
    await session.commit()
    return queued


async def enqueue_family_nudges(session: AsyncSession) -> int:
    """Ajakan mendukung ke anggota keluarga bila pemilik >= 3 hari belum check-in dan mengizinkan status check-in.

    Isinya hanya soal check-in (tanpa detail makanan atau hasil), nadanya mengajak, bukan melapor. Sekali per 3 hari.
    """
    cutoff = utcnow() - timedelta(days=3)
    links = (await session.execute(select(FamilyLink).where(FamilyLink.status == "active"))).scalars().all()
    queued = 0
    for link in links:
        if not link.permissions.get("checkin_status", True) or link.member_id is None:
            continue
        last = (
            await session.execute(select(func.max(Log.occurred_at)).where(Log.user_id == link.owner_id))
        ).scalar_one()
        if last is None or last > cutoff:
            continue
        wa = (await session.execute(select(WaLink).where(WaLink.user_id == link.member_id))).scalar_one_or_none()
        if wa is None:
            continue
        recent = (
            await session.execute(
                select(WaOutbox.id)
                .where(
                    WaOutbox.user_id == link.member_id,
                    WaOutbox.kind == "family",
                    WaOutbox.ref == str(link.id),
                    WaOutbox.created_at >= cutoff,
                )
                .limit(1)
            )
        ).first()
        if recent:
            continue
        owner = await session.get(User, link.owner_id)
        who = owner.display_name if owner and owner.display_name else "Anggota keluargamu"
        session.add(
            WaOutbox(
                jid=wa.jid,
                user_id=link.member_id,
                kind="family",
                ref=str(link.id),
                text=f"{who} sudah beberapa hari belum check-in di KIRA. Mungkin ini saat yang baik untuk "
                "menyapa dan mengajak ngobrol, tanpa menghakimi.",
            )
        )
        queued += 1
    await session.commit()
    return queued


async def purge_old_chats(session: AsyncSession) -> int:
    """Tengah malam WIB: obrolan hari-hari sebelumnya dibersihkan (satu riwayat obrolan per hari)."""
    from app.repos import messages as messages_repo

    return await messages_repo.purge_before_today(session)
