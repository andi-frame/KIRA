"""Pengingat rencana lewat WhatsApp: satu kali per ref, jam tenang, sudah tercatat -> lewati, batas 4/hari, kanal mati."""
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from app.models import PlanPreference, WaLink, WaOutbox
from app.repos import logs as logs_repo
from app.services import planner_jobs
from app.services.planner_jobs import due, enqueue_plan_reminders, in_quiet_hours

WIB = timezone(timedelta(hours=7))
DAY = datetime(2026, 10, 18, tzinfo=WIB)  # Minggu


def at(hh: int, mm: int, day: datetime = DAY) -> datetime:
    return day.replace(hour=hh, minute=mm)


async def setup_user(session_maker, make_user, *, whatsapp=True, linked=True, **prefs):
    uid = await make_user(birth_date=datetime(1998, 3, 14).date(), sex="male")
    async with session_maker() as s:
        if linked:
            s.add(WaLink(jid=f"{uid}@s.whatsapp.net", user_id=uid))
        s.add(PlanPreference(user_id=uid, channels={"app": True, "whatsapp": whatsapp},
                             reminders={"meals": True, "exercise": True, "sleep": True, "weekly_plan": True},
                             quiet_hours={"start": "22:30", "end": "05:00"}, **prefs))
        await s.commit()
    return uid


async def outbox(session_maker, uid):
    async with session_maker() as s:
        return (await s.execute(select(WaOutbox).where(WaOutbox.user_id == uid).order_by(WaOutbox.created_at))).scalars().all()


async def run(session_maker, now):
    async with session_maker() as s:
        return await enqueue_plan_reminders(s, now)


def test_jam_tenang_termasuk_yang_melewati_tengah_malam():
    q = {"start": "22:30", "end": "05:00"}
    assert in_quiet_hours(23 * 60, q) and in_quiet_hours(60, q) and not in_quiet_hours(12 * 60, q)
    assert in_quiet_hours(13 * 60, {"start": "12:00", "end": "14:00"})
    assert due(705, 705) and due(709, 705) and not due(710, 705)


async def test_pengingat_makan_siang_sekali_saja_dengan_usulan(session_maker, make_user):
    uid = await setup_user(session_maker, make_user, meal_times={"lunch": "12:00"})
    assert await run(session_maker, at(11, 45)) == 1
    assert await run(session_maker, at(11, 47)) == 0  # ref yang sama tidak diulang
    [msg] = await outbox(session_maker, uid)
    assert msg.kind == "plan_reminder" and msg.ref == "2026-10-18:lunch"
    assert "makan siang (12.00)" in msg.text and "Usulan:" in msg.text and "mmHg" not in msg.text


async def test_ringkasan_pagi_setelah_bangun(session_maker, make_user):
    uid = await setup_user(session_maker, make_user, wake_time="06:00")
    await run(session_maker, at(6, 15))
    msgs = await outbox(session_maker, uid)
    assert [m.ref for m in msgs] == ["2026-10-18:summary"] and msgs[0].text.startswith("Rencana hari ini:")


async def test_makan_yang_sudah_tercatat_dilewati(session_maker, make_user):
    uid = await setup_user(session_maker, make_user, meal_times={"lunch": "12:00"})
    async with session_maker() as s:
        await logs_repo.add_log(s, uid, kind="meal", source="text", occurred_at=at(11, 20), extracted={}, raw_text="x", items=[])
    assert await run(session_maker, at(11, 45)) == 0


async def test_tidak_ada_pesan_di_jam_tenang_kanal_mati_atau_tanpa_nomor(session_maker, make_user):
    quiet = await setup_user(session_maker, make_user, meal_times={"snack": "23:00"})
    off = await setup_user(session_maker, make_user, whatsapp=False, meal_times={"lunch": "12:00"})
    unlinked = await setup_user(session_maker, make_user, linked=False, meal_times={"lunch": "12:00"})
    await run(session_maker, at(22, 45))  # pengingat selingan 23.00 jatuh di jam tenang (22.30-05.00)
    await run(session_maker, at(11, 45))
    assert not any(m.ref.endswith(":snack") for m in await outbox(session_maker, quiet))
    for uid in (off, unlinked):
        assert await outbox(session_maker, uid) == []


async def test_batas_empat_pesan_per_hari_termasuk_jenis_lain(session_maker, make_user):
    uid = await setup_user(session_maker, make_user, meal_times={"breakfast": "07:00", "lunch": "12:00", "snack": "15:00",
                                                                "dinner": "18:00"})
    async with session_maker() as s:
        s.add(WaOutbox(jid="x", user_id=uid, kind="reminder", text="check-in", created_at=at(5, 30)))
        await s.commit()
    for now in (at(6, 45), at(11, 45), at(14, 45), at(17, 45)):
        await run(session_maker, now)
    msgs = await outbox(session_maker, uid)
    assert len(msgs) == planner_jobs.MAX_WA_PER_DAY
    assert [m.ref for m in msgs if m.kind == "plan_reminder"] == ["2026-10-18:breakfast", "2026-10-18:lunch", "2026-10-18:snack"]


async def test_rencana_mingguan_minggu_sore(session_maker, make_user):
    uid = await setup_user(session_maker, make_user)
    await run(session_maker, at(18, 0))
    assert any(m.ref == "2026-W42:week" for m in await outbox(session_maker, uid))
    other_day = await setup_user(session_maker, make_user)
    await run(session_maker, at(18, 0, DAY - timedelta(days=1)))
    assert not any(m.ref.endswith(":week") for m in await outbox(session_maker, other_day))


@pytest.mark.parametrize("hour,minute", [(21, 45)])
async def test_pengingat_tidur_dari_jam_bangun_dan_target(session_maker, make_user, hour, minute):
    uid = await setup_user(session_maker, make_user, wake_time="06:00")  # belum ada catatan tidur -> target 8 jam -> 22.00
    await run(session_maker, at(hour, minute))
    assert any(m.ref == "2026-10-18:sleep" and "22.00" in m.text for m in await outbox(session_maker, uid))
