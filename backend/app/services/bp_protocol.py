"""Protokol ukur tensi di rumah 7 hari (ESH 2021): pencatatan bacaan, ringkasan harian, dan penutupan menjadi satu hasil.

Perhitungan ada di `core_calc.hbpm`; modul ini hanya menyambungkannya ke basis data. Hasil akhir (rata-rata) disimpan
sebagai SATU hasil cek tensi sehingga proyeksi, tren, dan ringkasan dokter memakainya, bukan tiap bacaan terpisah.
"""
import uuid
from datetime import datetime, timedelta

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core_calc.constants import HBPM_HOME_THRESHOLD, HBPM_MIN_DAYS, HBPM_MIN_READINGS, HBPM_PROTOCOL_DAYS
from app.core_calc.hbpm import SESSIONS, HbpmSummary, Reading, protocol_day_index, summarize, validate_reading
from app.core_calc.red_flags import RedFlag, detect_red_flags
from app.models import BpProtocol, BpReading
from app.services import risk
from app.timeutil import local_date, utcnow

MAX_PER_SESSION = 4  # protokol minta 2 bacaan; sisanya ruang untuk salah ukur
BACKDATE = timedelta(hours=6)  # bacaan pagi sebelum protokol dimulai di aplikasi masih wajar
GRACE_DAYS = 3  # bacaan susulan setelah hari ke-7


class ProtocolError(Exception):
    """Kesalahan yang pesannya boleh langsung ditampilkan ke pengguna."""


async def active(session: AsyncSession, user_id: uuid.UUID) -> BpProtocol | None:
    stmt = select(BpProtocol).where(BpProtocol.user_id == user_id, BpProtocol.status == "active")
    return (await session.execute(stmt)).scalar_one_or_none()


async def latest(session: AsyncSession, user_id: uuid.UUID) -> BpProtocol | None:
    """Protokol aktif, atau yang terakhir selesai (untuk menampilkan hasilnya)."""
    current = await active(session, user_id)
    if current is not None:
        return current
    stmt = (
        select(BpProtocol)
        .where(BpProtocol.user_id == user_id, BpProtocol.status == "completed")
        .order_by(BpProtocol.completed_at.desc())
        .limit(1)
    )
    return (await session.execute(stmt)).scalar_one_or_none()


async def start(session: AsyncSession, user_id: uuid.UUID) -> BpProtocol:
    if await active(session, user_id) is not None:
        raise ProtocolError("Kamu masih punya putaran ukur tensi yang berjalan. Selesaikan atau batalkan dulu.")
    protocol = BpProtocol(user_id=user_id)
    session.add(protocol)
    await session.commit()
    await session.refresh(protocol)
    return protocol


async def _readings(session: AsyncSession, protocol_id: uuid.UUID) -> list[BpReading]:
    stmt = select(BpReading).where(BpReading.protocol_id == protocol_id).order_by(BpReading.measured_at)
    return list((await session.execute(stmt)).scalars().all())


def _as_core(rows: list[BpReading]) -> list[Reading]:
    return [Reading(r.measured_at, r.sys, r.dia, r.session) for r in rows]


async def add_reading(
    session: AsyncSession,
    user_id: uuid.UUID,
    *,
    sys: int,
    dia: int,
    session_name: str,
    measured_at: datetime | None = None,
    pulse: int | None = None,
) -> tuple[BpReading | None, RedFlag | None]:
    """Menyimpan satu bacaan. Bacaan berbahaya TIDAK disimpan; red flag dikembalikan agar pengguna diarahkan ke faskes."""
    protocol = await active(session, user_id)
    if protocol is None:
        raise ProtocolError("Belum ada putaran ukur tensi yang berjalan. Mulai dulu.")
    if session_name not in SESSIONS:
        raise ProtocolError("Sesi harus 'morning' atau 'evening'.")
    try:
        validate_reading(sys, dia)
    except ValueError:
        raise ProtocolError("Angka tensi tampak tidak mungkin. Cek lagi hasil di layar tensimeter.") from None
    flag = detect_red_flags(bp=(sys, dia))
    if flag is not None:
        return None, flag

    now = utcnow()
    at = measured_at or now
    if at > now + timedelta(minutes=5):
        raise ProtocolError("Waktu ukur tidak boleh di masa depan.")
    if at < protocol.started_at - BACKDATE:
        raise ProtocolError("Waktu ukur ini sebelum putaran dimulai.")
    if at > protocol.started_at + timedelta(days=HBPM_PROTOCOL_DAYS + GRACE_DAYS):
        raise ProtocolError("Putaran ini sudah lewat 7 hari. Selesaikan dulu, lalu mulai putaran baru.")

    same = [r for r in await _readings(session, protocol.id) if local_date(r.measured_at) == local_date(at) and r.session == session_name]
    if len(same) >= MAX_PER_SESSION:
        raise ProtocolError(f"Sudah {MAX_PER_SESSION} bacaan untuk sesi ini. Cukup 2 bacaan per sesi.")

    row = BpReading(protocol_id=protocol.id, user_id=user_id, measured_at=at, sys=sys, dia=dia, session=session_name,
                    pulse=pulse)
    session.add(row)
    await session.commit()
    return row, None


def _calendar(protocol: BpProtocol, summary: HbpmSummary) -> list[dict]:
    """Tujuh hari protokol dari tanggal mulai, lengkap dengan hari tanpa bacaan (nol, bukan hilang)."""
    counts = {d.day: d for d in summary.days}
    start = local_date(protocol.started_at)
    today = local_date(utcnow())
    out = []
    for i in range(HBPM_PROTOCOL_DAYS):
        day = start + timedelta(days=i)
        c = counts.get(day)
        out.append({
            "date": day.isoformat(),
            "morning": c.morning if c else 0,
            "evening": c.evening if c else 0,
            "discarded": bool(c and c.discarded),
            "is_today": day == today,
        })
    return out


def _summary_out(s: HbpmSummary) -> dict:
    return {
        "valid": s.valid, "avg_sys": s.avg_sys, "avg_dia": s.avg_dia, "range": s.range,
        "readings_used": s.readings_used, "days_used": s.days_used, "missing": s.missing,
    }


async def status(session: AsyncSession, user_id: uuid.UUID) -> dict:
    protocol = await latest(session, user_id)
    guide = {
        "protocol_days": HBPM_PROTOCOL_DAYS, "min_days": HBPM_MIN_DAYS, "min_readings": HBPM_MIN_READINGS,
        "home_threshold": {"sys": HBPM_HOME_THRESHOLD[0], "dia": HBPM_HOME_THRESHOLD[1]},
        "source": "ESH 2021 (Stergiou dkk., J Hypertens 39:1293-1302)",
    }
    if protocol is None:
        return {"protocol": None, "guide": guide}
    rows = await _readings(session, protocol.id)
    summary = summarize(_as_core(rows))
    today = local_date(utcnow())
    pulses = [r.pulse for r in rows if r.pulse]
    out = {
        "avg_pulse": round(sum(pulses) / len(pulses)) if pulses else None,
        "pulse_readings": len(pulses),
        "id": str(protocol.id),
        "status": protocol.status,
        "started_at": protocol.started_at.isoformat(),
        "day_index": protocol_day_index(local_date(protocol.started_at), today),
        "days": _calendar(protocol, summary),
        "summary": _summary_out(summary),
        "can_finish": protocol.status == "active" and summary.valid,
        "over": today > local_date(protocol.started_at) + timedelta(days=HBPM_PROTOCOL_DAYS - 1),
    }
    if protocol.status == "completed":
        out["result"] = {
            "avg_sys": protocol.avg_sys, "avg_dia": protocol.avg_dia, "readings_used": protocol.readings_used,
            "completed_at": protocol.completed_at.isoformat() if protocol.completed_at else None,
            "range": "hypertension_range"
            if (protocol.avg_sys or 0) >= HBPM_HOME_THRESHOLD[0] or (protocol.avg_dia or 0) >= HBPM_HOME_THRESHOLD[1]
            else "below_threshold",
        }
    return {"protocol": out, "guide": guide}


async def finish(session: AsyncSession, user_id: uuid.UUID) -> tuple[BpProtocol, RedFlag | None]:
    protocol = await active(session, user_id)
    if protocol is None:
        raise ProtocolError("Belum ada putaran ukur tensi yang berjalan.")
    rows = await _readings(session, protocol.id)
    summary = summarize(_as_core(rows))
    if not summary.valid:
        raise ProtocolError(summary.missing or "Belum cukup bacaan.")
    pulses = [r.pulse for r in rows if r.pulse]
    value = {
        "sys": round(summary.avg_sys), "dia": round(summary.avg_dia),
        "avg_sys": summary.avg_sys, "avg_dia": summary.avg_dia,
        "protocol": str(protocol.id), "readings": summary.readings_used,
    }
    if pulses:
        value["pulse"] = round(sum(pulses) / len(pulses))
    outcome = await risk.record_result(session, user_id, "blood_pressure", value, "self", commit=False)
    if outcome.red_flag is not None:
        await session.rollback()
        return protocol, outcome.red_flag
    protocol.status, protocol.completed_at = "completed", utcnow()
    protocol.avg_sys, protocol.avg_dia, protocol.readings_used = summary.avg_sys, summary.avg_dia, summary.readings_used
    protocol.result_id = outcome.result_id
    await session.commit()
    return protocol, None


async def cancel(session: AsyncSession, user_id: uuid.UUID) -> bool:
    protocol = await active(session, user_id)
    if protocol is None:
        return False
    protocol.status = "cancelled"
    await session.commit()
    return True
