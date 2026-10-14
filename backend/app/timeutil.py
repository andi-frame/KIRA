from datetime import date, datetime, timedelta, timezone

WIB = timezone(timedelta(hours=7))


def utcnow() -> datetime:
    return datetime.now(timezone.utc)


def start_of_today_utc() -> datetime:
    """Awal hari ini menurut WIB, dinyatakan dalam UTC."""
    now_wib = utcnow().astimezone(WIB)
    midnight = now_wib.replace(hour=0, minute=0, second=0, microsecond=0)
    return midnight.astimezone(timezone.utc)


def local_date(moment: datetime) -> date:
    return moment.astimezone(WIB).date()
