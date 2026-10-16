"""Penjadwal pekerjaan latar (APScheduler, dalam proses backend; cukup untuk demo)."""
import logging

from apscheduler.schedulers.asyncio import AsyncIOScheduler
from apscheduler.triggers.cron import CronTrigger

from app.services import check_followup, jobs, planner_jobs

log = logging.getLogger("kira.scheduler")
TIMEZONE = "Asia/Jakarta"


def _wrap(session_factory, job):
    async def run() -> None:
        try:
            async with session_factory() as session:
                count = await job(session)
            log.info("%s selesai (%s)", job.__name__, count)
        except Exception:  # noqa: BLE001 - satu job gagal tidak boleh mematikan penjadwal
            log.exception("%s gagal", job.__name__)

    return run


def build_scheduler(session_factory) -> AsyncIOScheduler:
    scheduler = AsyncIOScheduler(timezone=TIMEZONE)
    scheduler.add_job(
        _wrap(session_factory, jobs.build_weekly_summaries),
        CronTrigger(day_of_week="mon", hour=0, minute=10, timezone=TIMEZONE),
        id="weekly_summaries",
    )
    scheduler.add_job(
        _wrap(session_factory, jobs.purge_old_chats),
        CronTrigger(hour=0, minute=5, timezone=TIMEZONE),
        id="purge_old_chats",
    )
    scheduler.add_job(
        _wrap(session_factory, jobs.evaluate_checks_for_all),
        CronTrigger(hour=2, minute=0, timezone=TIMEZONE),
        id="nightly_checks",
    )
    scheduler.add_job(
        _wrap(session_factory, jobs.enqueue_reminders),
        CronTrigger(hour=19, minute=0, timezone=TIMEZONE),
        id="daily_reminders",
    )
    scheduler.add_job(
        _wrap(session_factory, check_followup.enqueue_followups),
        CronTrigger(hour=10, minute=0, timezone=TIMEZONE),
        id="check_followups",
    )
    scheduler.add_job(
        _wrap(session_factory, jobs.enqueue_family_nudges),
        CronTrigger(hour=19, minute=30, timezone=TIMEZONE),
        id="family_nudges",
    )
    scheduler.add_job(
        _wrap(session_factory, planner_jobs.enqueue_plan_reminders),
        CronTrigger(minute=f"*/{planner_jobs.JOB_INTERVAL_MINUTES}", timezone=TIMEZONE),
        id="plan_reminders",
    )
    return scheduler
