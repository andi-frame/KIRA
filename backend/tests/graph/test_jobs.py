from datetime import date, datetime, timedelta, timezone

from sqlalchemy import text

from app.repos import logs as logs_repo
from app.repos import summaries as summaries_repo
from app.services.jobs import build_weekly_summaries, evaluate_checks_for_all, week_bounds
from app.timeutil import WIB

TODAY = date(2026, 10, 14)  # Rabu; minggu lalu = Senin 5 Okt .. Minggu 11 Okt 2026


def at(day: date, hour: int) -> datetime:
    return datetime.combine(day, datetime.min.time(), tzinfo=WIB).replace(hour=hour).astimezone(timezone.utc)


async def add(session, uid, day, kind, extracted, items=(), hour=12):
    await logs_repo.add_log(session, uid, kind=kind, source="text", occurred_at=at(day, hour),
                            extracted=extracted, raw_text="x", items=list(items))


def test_week_bounds_is_the_previous_monday_to_sunday():
    assert week_bounds(TODAY) == (date(2026, 10, 5), date(2026, 10, 11))
    assert week_bounds(date(2026, 10, 12)) == (date(2026, 10, 5), date(2026, 10, 11))  # Senin pun: minggu lalu


async def test_weekly_summary_aggregates_only_that_weeks_logs(session_maker, make_user):
    uid = await make_user()
    sweet = logs_repo.ItemData(name="es teh manis", portion_g=250, sugar_g=20)
    async with session_maker() as s:
        for d in (date(2026, 10, 5), date(2026, 10, 6)):
            await add(s, uid, d, "drink", {"name": "es teh manis", "count": 1}, [sweet])
            await add(s, uid, d, "sleep", {"hours": 5.0}, hour=7)
        await add(s, uid, date(2026, 10, 7), "activity", {"kind": "jalan kaki", "minutes": 30})
        await add(s, uid, date(2026, 10, 12), "drink", {"name": "es teh manis", "count": 3}, [sweet])  # minggu ini
        await build_weekly_summaries(s, today=TODAY)
        summary = await summaries_repo.latest(s, uid)
    assert summary.week_start == date(2026, 10, 5)
    m = summary.metrics
    assert m["days_logged"] == 3
    assert m["sweet_drinks_per_day"] == round(2 / 3, 2)
    assert m["sleep_hours_avg"] == 5.0
    assert m["active_minutes_per_day"] == 10.0
    assert "5 Okt" in summary.summary_text and "11 Okt" in summary.summary_text
    assert "tidur" in summary.summary_text.lower()


async def test_weekly_summary_is_idempotent_and_skips_users_without_logs(session_maker, make_user):
    active, quiet = await make_user(), await make_user()
    async with session_maker() as s:
        await add(s, active, date(2026, 10, 6), "sleep", {"hours": 6.0}, hour=7)
        await build_weekly_summaries(s, today=TODAY)
        await build_weekly_summaries(s, today=TODAY)
        rows = (await s.execute(text("select user_id from weekly_summaries"))).all()
    assert len(rows) == 1 and rows[0].user_id == active
    assert quiet != active


async def test_nightly_evaluation_creates_a_recommendation_for_every_user(session_maker, make_user):
    a, b = await make_user(), await make_user()
    async with session_maker() as s:
        evaluated = await evaluate_checks_for_all(s)
        rows = (await s.execute(text("select user_id, status from check_recommendations"))).all()
    assert evaluated == 2
    assert {r.user_id for r in rows} == {a, b} and {r.status for r in rows} == {"open"}
