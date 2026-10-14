from apscheduler.triggers.cron import CronTrigger

from app.scheduler import build_scheduler


def test_scheduler_registers_the_four_jobs_in_wib():
    scheduler = build_scheduler(session_factory=lambda: None)
    jobs = {j.id: j for j in scheduler.get_jobs()}
    assert set(jobs) == {"weekly_summaries", "nightly_checks", "daily_reminders", "family_nudges"}
    assert all(isinstance(j.trigger, CronTrigger) for j in jobs.values())
    assert all(str(j.trigger.timezone) == "Asia/Jakarta" for j in jobs.values())
    assert jobs["weekly_summaries"].trigger.fields[4].name == "day_of_week"
    assert not scheduler.running  # hanya dibangun; dijalankan oleh lifespan aplikasi
