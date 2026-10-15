from datetime import date, datetime, timedelta, timezone

import pytest

from app.core_calc.steps import MODERATE_CADENCE, StepSegment, moderate_minutes_by_day

WIB = timezone(timedelta(hours=7))


def seg(hour: int, minute: int, minutes: int, steps: int, day: int = 14) -> StepSegment:
    start = datetime(2026, 10, day, hour, minute, tzinfo=WIB)
    return StepSegment(start=start, end=start + timedelta(minutes=minutes), steps=steps)


def test_ambang_kadensi_sedang_100_langkah_per_menit():
    assert MODERATE_CADENCE == 100


def test_menit_dihitung_hanya_dari_segmen_berkadensi_sedang_ke_atas():
    by_day = moderate_minutes_by_day([seg(7, 0, 10, 1100), seg(9, 0, 10, 600), seg(18, 0, 5, 500)])
    assert by_day == {date(2026, 10, 14): 15}  # 110/mnt dan 100/mnt lolos; 60/mnt tidak


def test_hari_dengan_langkah_tetapi_tanpa_menit_sedang_tetap_tercatat_nol():
    assert moderate_minutes_by_day([seg(9, 0, 60, 3000)]) == {date(2026, 10, 14): 0}


def test_dikelompokkan_per_hari_waktu_wib():
    by_day = moderate_minutes_by_day([seg(23, 50, 5, 600, day=14), seg(0, 10, 5, 600, day=15)])
    assert by_day == {date(2026, 10, 14): 5, date(2026, 10, 15): 5}


def test_segmen_utc_dikonversi_ke_hari_wib():
    start = datetime(2026, 10, 14, 18, 0, tzinfo=timezone.utc)  # 01:00 WIB tanggal 15
    by_day = moderate_minutes_by_day([StepSegment(start, start + timedelta(minutes=10), 1200)])
    assert by_day == {date(2026, 10, 15): 10}


@pytest.mark.parametrize(
    "segment",
    [
        seg(9, 0, 10, 3000),  # 300 langkah/menit: tidak mungkin, abaikan
        StepSegment(datetime(2026, 10, 14, 9, tzinfo=WIB), datetime(2026, 10, 14, 9, tzinfo=WIB), 100),  # durasi nol
        StepSegment(datetime(2026, 10, 14, 9, tzinfo=WIB), datetime(2026, 10, 14, 8, tzinfo=WIB), 100),  # terbalik
        seg(9, 0, 10, -5),
    ],
)
def test_segmen_tidak_wajar_diabaikan(segment):
    assert moderate_minutes_by_day([segment]) == {}
