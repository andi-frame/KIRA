"""Pengingat rencana lewat WhatsApp (job tiap 5 menit, WIB, per pengguna sesuai preferensi rencana).

Hanya untuk akun yang menyalakan kanal WhatsApp di preferensi rencana dan punya nomor tertaut. Satu `ref` satu kali,
tidak di jam tenang, dilewati bila waktu makan itu sudah tercatat, dan semua pesan WhatsApp ke pengguna (jenis apa pun)
dibatasi 4 per hari. Isi pesan boleh memuat nama usulan dan energi, tidak pernah hasil pemeriksaan.
"""
import uuid
from datetime import date, datetime, timedelta

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.planner import SLOT_LABELS
from app.models import Log, PlanPreference, User, WaLink, WaOutbox
from app.services import plan as plan_service
from app.timeutil import WIB, local_date, utcnow

MAX_WA_PER_DAY = 4
LEAD_MINUTES = 15  # kirim mulai 15 menit sebelum waktunya; job 5 menit -> tiba 10-15 menit sebelumnya
JOB_INTERVAL_MINUTES = 5
SUMMARY_AFTER_WAKE_MINUTES = 15
WEEKLY_DAY, WEEKLY_TIME = 6, "18:00"  # Minggu 18.00
SLEEP_CHECK_FROM, SLEEP_CHECK_UNTIL = 18 * 60, 2 * 60


def _minutes(hhmm: str) -> int:
    h, m = hhmm.split(":")
    return int(h) * 60 + int(m)


def in_quiet_hours(now_min: int, quiet: dict | None) -> bool:
    if not quiet:
        return False
    start, end = _minutes(quiet["start"]), _minutes(quiet["end"])
    return start <= now_min < end if start <= end else (now_min >= start or now_min < end)


def due(now_min: int, send_at: int) -> bool:
    return send_at <= now_min < send_at + JOB_INTERVAL_MINUTES


def _fmt(hhmm: str) -> str:
    return hhmm.replace(":", ".")


async def _sent_today(session: AsyncSession, user_id: uuid.UUID, since: datetime) -> int:
    return (await session.execute(select(func.count()).select_from(WaOutbox).where(
        WaOutbox.user_id == user_id, WaOutbox.created_at >= since))).scalar_one()


async def _exists(session: AsyncSession, user_id: uuid.UUID, ref: str) -> bool:
    return (await session.execute(select(WaOutbox.id).where(WaOutbox.user_id == user_id, WaOutbox.ref == ref).limit(1))).first() is not None


async def _logged_slots(session: AsyncSession, user_id: uuid.UUID, today: date) -> set[str]:
    since = datetime.combine(today, datetime.min.time(), tzinfo=WIB)
    logs = (await session.execute(select(Log).where(
        Log.user_id == user_id, Log.kind == "meal", Log.occurred_at >= since))).scalars().all()
    return {plan_service.meal_slot(lg) for lg in logs}


async def due_messages(session: AsyncSession, user_id: uuid.UUID, prefs: dict, now: datetime) -> list[tuple[str, str, str]]:
    """(kind, ref, text) yang jatuh tempo sekarang untuk satu pengguna, belum memperhitungkan batas harian."""
    local = now.astimezone(WIB)
    today, now_min = local.date(), local.hour * 60 + local.minute
    reminders = prefs["reminders"]
    out: list[tuple[str, str, str]] = []
    plan = None

    async def today_plan() -> dict:
        nonlocal plan
        if plan is None:
            plan = await plan_service.plan_today(session, user_id, now)
        return plan

    if due(now_min, _minutes(prefs["wake_time"]) + SUMMARY_AFTER_WAKE_MINUTES):
        p = await today_plan()
        meals = ", ".join(f"{m['label']} {m['title']}" for m in p["meals"] if m.get("title") and m["slot"] != "snack")
        ex = p["exercise"]
        extra = f" Olahraga: {ex['activity']} {ex['minutes']} menit." if ex and ex.get("minutes") else ""
        out.append(("plan", f"{today}:summary", f"Rencana hari ini: {meals}.{extra} Tidur jam {_fmt(p['sleep']['bedtime'])}. "
                                                 "Ini usulan, boleh kamu ubah."))
    # Ringkasan pagi sudah menyebut usulan makan: pengingat makan pada putaran yang sama tidak perlu.
    if reminders.get("meals") and not out:
        done = await _logged_slots(session, user_id, today)
        for slot, t in prefs["meal_times"].items():
            if slot in done or not due(now_min, _minutes(t) - LEAD_MINUTES):
                continue
            meal = next((m for m in (await today_plan())["meals"] if m["slot"] == slot), None)
            idea = f" Usulan: {meal['title']} (sekitar {meal['totals']['kcal']:.0f} kkal)." if meal and meal.get("title") else ""
            out.append(("plan_reminder", f"{today}:{slot}",
                        f"Sebentar lagi waktunya {SLOT_LABELS[slot]} ({_fmt(t)}).{idea} Ceritakan di sini setelah makan ya."))
    if reminders.get("exercise") and due(now_min, _minutes(prefs["exercise_time"]) - LEAD_MINUTES):
        ex = (await today_plan())["exercise"]
        if ex and ex.get("minutes") and not ex.get("done") and not ex.get("blocked"):
            out.append(("plan_reminder", f"{today}:exercise",
                        f"Jam {_fmt(prefs['exercise_time'])} waktunya {ex['activity']} {ex['minutes']} menit. Pelan-pelan saja ya."))
    # Jam tidur bergantung pada rencana (rata-rata tidur terkini); hanya dihitung pada malam hari.
    if reminders.get("sleep") and (now_min >= SLEEP_CHECK_FROM or now_min < SLEEP_CHECK_UNTIL):
        bedtime = (await today_plan())["sleep"]["bedtime"]
        if due(now_min, (_minutes(bedtime) - LEAD_MINUTES) % (24 * 60)):
            out.append(("plan_reminder", f"{today}:sleep",
                        f"Sebentar lagi jam tidurmu ({_fmt(bedtime)}). Mulai bersiap, letakkan ponsel ya."))
    if reminders.get("weekly_plan") and today.weekday() == WEEKLY_DAY and due(now_min, _minutes(WEEKLY_TIME)):
        iso = today.isocalendar()
        out.append(("plan", f"{iso.year}-W{iso.week:02d}:week",
                    "Rencana minggu depan sudah siap di aplikasi KIRA (menu Rencana). Balas 'rencana minggu' untuk ringkasannya."))
    return out


async def enqueue_plan_reminders(session: AsyncSession, now: datetime | None = None) -> int:
    now = now or utcnow()
    local = now.astimezone(WIB)
    since = datetime.combine(local_date(now), datetime.min.time(), tzinfo=WIB)
    rows = (await session.execute(select(WaLink, PlanPreference).join(
        PlanPreference, PlanPreference.user_id == WaLink.user_id))).all()
    queued = 0
    for link, row in rows:
        prefs = plan_service.prefs_out(row)
        if not prefs["channels"].get("whatsapp") or in_quiet_hours(local.hour * 60 + local.minute, prefs["quiet_hours"]):
            continue
        budget = MAX_WA_PER_DAY - await _sent_today(session, link.user_id, since)
        for kind, ref, text in await due_messages(session, link.user_id, prefs, now):
            if budget <= 0:
                break
            if await _exists(session, link.user_id, ref):
                continue
            user = await session.get(User, link.user_id)
            name = f"{user.display_name}, " if user and user.display_name else ""
            # created_at = waktu job (bukan jam basis data) supaya batas harian dihitung pada hari yang sama
            session.add(WaOutbox(jid=link.jid, user_id=link.user_id, kind=kind, ref=ref, created_at=now,
                                 text=f"{name}{text}" if name else text))
            budget -= 1
            queued += 1
        await session.flush()
    await session.commit()
    return queued
