from datetime import datetime, timedelta

import pytest

from app.core_calc.hbpm import Reading, protocol_day_index, summarize, validate_reading
from app.timeutil import WIB

DAY1 = datetime(2026, 10, 5, 7, 30, tzinfo=WIB)


def reading(day: int, session: str, sys: int, dia: int, minute: int = 0) -> Reading:
    hour = 7 if session == "morning" else 20
    return Reading(DAY1.replace(hour=hour, minute=minute) + timedelta(days=day), sys, dia, session)


def full_day(day: int, sys: int, dia: int) -> list[Reading]:
    """Protokol lengkap satu hari: dua bacaan berjarak 1 menit, pagi dan malam."""
    return [reading(day, s, sys, dia, m) for s in ("morning", "evening") for m in (0, 1)]


def test_tanpa_bacaan_belum_bisa_dinilai_dan_menjelaskan_kekurangannya():
    s = summarize([])
    assert not s.valid and s.avg_sys is None and s.days == []
    assert "3 hari lagi" in s.missing and "12 bacaan lagi" in s.missing


def test_hari_pertama_dibuang_dari_rata_rata():
    readings = full_day(0, 190, 120)  # hari 1: tinggi sekali, harus dibuang
    for d in (1, 2, 3):
        readings += full_day(d, 124, 80)
    s = summarize(readings)
    assert s.valid and s.avg_sys == 124.0 and s.avg_dia == 80.0
    assert s.days[0].discarded and not s.days[1].discarded
    assert s.readings_used == 12 and s.days_used == 3


def test_butuh_minimal_tiga_hari_dan_dua_belas_bacaan_setelah_hari_pertama():
    only_two_days = full_day(0, 130, 80) + full_day(1, 130, 80) + full_day(2, 130, 80)  # 2 hari terpakai, 8 bacaan
    s = summarize(only_two_days)
    assert not s.valid and s.avg_sys is None and s.range is None
    assert "1 hari lagi" in s.missing and "4 bacaan lagi" in s.missing

    # tiga hari terpakai tetapi hanya 9 bacaan (3 per hari)
    sparse = full_day(0, 130, 80)
    for d in (1, 2, 3):
        sparse += [reading(d, "morning", 130, 80, 0), reading(d, "morning", 130, 80, 1), reading(d, "evening", 130, 80)]
    s2 = summarize(sparse)
    assert not s2.valid and s2.days_used == 3 and s2.readings_used == 9
    assert "hari lagi" not in s2.missing and "3 bacaan lagi" in s2.missing


@pytest.mark.parametrize(
    "sys,dia,expected",
    [(134, 84, "below_threshold"), (135, 80, "hypertension_range"), (120, 85, "hypertension_range"), (134.4, 84.4, "below_threshold")],
)
def test_ambang_rumah_135_85_salah_satu_cukup(sys, dia, expected):
    readings = full_day(0, 120, 70)
    for d in (1, 2, 3):
        readings += full_day(d, sys if isinstance(sys, int) else 134, dia if isinstance(dia, int) else 84)
    if isinstance(sys, float):  # rata-rata 134,4 dari bacaan bulat: campur 134 dan 135
        readings = full_day(0, 120, 70)
        for d in (1, 2, 3):
            readings += [reading(d, "morning", 134, 84, 0), reading(d, "morning", 134, 84, 1),
                         reading(d, "evening", 135, 85, 0), reading(d, "evening", 134, 84, 1)]
    s = summarize(readings)
    assert s.valid and s.range == expected


def test_rata_rata_bulat_satu_desimal_dan_semua_bacaan_ikut():
    readings = full_day(0, 150, 95)
    for d, (sys, dia) in zip((1, 2, 3), [(128, 82), (131, 79), (125, 76)]):
        readings += full_day(d, sys, dia)
    s = summarize(readings)
    assert s.avg_sys == pytest.approx(128.0) and s.avg_dia == pytest.approx(79.0)


def test_urutan_masukan_tidak_memengaruhi_hasil():
    readings = full_day(0, 120, 80) + full_day(1, 130, 85) + full_day(2, 128, 84) + full_day(3, 126, 82)
    assert summarize(readings) == summarize(list(reversed(readings)))


def test_hari_dihitung_menurut_tanggal_lokal_bukan_utc():
    # 23.30 WIB = 16.30 UTC hari yang sama; 00.30 WIB = 17.30 UTC hari sebelumnya. Tanggal lokal yang berlaku.
    late = Reading(datetime(2026, 10, 5, 23, 30, tzinfo=WIB), 130, 80, "evening")
    after_midnight = Reading(datetime(2026, 10, 6, 0, 30, tzinfo=WIB), 130, 80, "morning")
    s = summarize([late, after_midnight])
    assert [d.day.isoformat() for d in s.days] == ["2026-10-05", "2026-10-06"]


def test_cacah_pagi_dan_malam_per_hari():
    s = summarize([reading(0, "morning", 120, 80), reading(0, "morning", 121, 81, 1), reading(0, "evening", 119, 79)])
    assert (s.days[0].morning, s.days[0].evening) == (2, 1)


def test_validasi_bacaan_menolak_nilai_mustahil():
    validate_reading(120, 80)
    for sys, dia in [(400, 80), (120, 120), (40, 30), (120, 20)]:
        with pytest.raises(ValueError):
            validate_reading(sys, dia)


def test_indeks_hari_protokol_dibatasi_satu_sampai_tujuh():
    start = DAY1.date()
    assert protocol_day_index(start, start) == 1
    assert protocol_day_index(start, start + timedelta(days=3)) == 4
    assert protocol_day_index(start, start + timedelta(days=30)) == 7
    assert protocol_day_index(start, start - timedelta(days=2)) == 1
