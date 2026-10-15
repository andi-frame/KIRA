import pytest

from app.core_calc.patterns import MIN_PER_GROUP, compare_by_sleep, compare_metric


def day(date: str, sleep, sugar=40.0, sweet=1.0, active=20.0) -> dict:
    return {"date": date, "sleep_hours": sleep, "sugar_g": sugar, "sweet_drinks": sweet, "active_minutes": active}


def week(short_sugar: float, other_sugar: float, n_short=3, n_other=3) -> list[dict]:
    days = [day(f"2026-10-{i + 1:02d}", 5.0, sugar=short_sugar) for i in range(n_short)]
    days += [day(f"2026-10-{i + 10:02d}", 7.5, sugar=other_sugar) for i in range(n_other)]
    return days


def test_butuh_minimal_tiga_hari_di_kedua_kelompok_atau_diam():
    assert compare_metric("x", "X", "g", [1, 2], [1, 2, 3]) is None
    assert compare_metric("x", "X", "g", [1, 2, 3], [1, 2]) is None
    assert compare_metric("x", "X", "g", [1, 2, 3], [1, 2, 3]) is not None
    assert MIN_PER_GROUP == 3


def test_membandingkan_rata_rata_hari_tidur_pendek_dengan_hari_lain():
    r = compare_by_sleep(week(short_sugar=70, other_sugar=40))
    sugar = next(c for c in r["comparisons"] if c.key == "sugar_g")
    assert (sugar.short_avg, sugar.other_avg, sugar.diff) == (70, 40, 30)
    assert (sugar.n_short, sugar.n_other) == (3, 3)
    assert r["short_days"] == 3 and r["other_days"] == 3 and r["needs_more_data"] is False


def test_enam_jam_tepat_bukan_tidur_pendek():
    days = [day(f"2026-10-0{i}", 6.0) for i in range(1, 4)] + [day(f"2026-10-1{i}", 5.9) for i in range(3)]
    r = compare_by_sleep(days)
    assert r["short_days"] == 3 and r["other_days"] == 3


def test_hari_tanpa_catatan_tidur_tidak_ikut_dan_nilai_kosong_dilewati():
    days = week(70, 40) + [day("2026-10-20", None, sugar=999)]
    r = compare_by_sleep(days)
    assert r["short_days"] + r["other_days"] == 6
    assert next(c for c in r["comparisons"] if c.key == "sugar_g").other_avg == 40

    holes = week(70, 40)
    for d in holes[:3]:
        d["active_minutes"] = None
    r2 = compare_by_sleep(holes)
    assert "active_minutes" not in {c.key for c in r2["comparisons"]}  # kelompok pendek tanpa data aktif


def test_data_terlalu_sedikit_menyatakan_perlu_lebih_banyak_bukan_angka_palsu():
    r = compare_by_sleep(week(70, 40, n_short=2, n_other=5))
    assert r["comparisons"] == [] and r["needs_more_data"] is True
    assert compare_by_sleep([])["needs_more_data"] is True


def test_tekanan_darah_dibandingkan_per_hari_yang_sama():
    days = week(60, 40)
    bp = {"2026-10-01": [138.0, 140.0], "2026-10-02": [136.0], "2026-10-10": [122.0, 124.0], "2026-10-11": [120.0], "2026-10-99": [200.0]}
    r = compare_by_sleep(days, bp)
    s = next(c for c in r["comparisons"] if c.key == "systolic")
    assert s.short_avg == pytest.approx(138.0) and s.other_avg == pytest.approx(122.0)
    assert (s.n_short, s.n_other) == (3, 3)  # bacaan di tanggal tanpa catatan tidur (10-99) tidak ikut


def test_bacaan_tekanan_darah_kurang_dari_tiga_per_kelompok_tidak_ditampilkan():
    r = compare_by_sleep(week(60, 40), {"2026-10-01": [138.0, 140.0], "2026-10-10": [122.0, 124.0, 120.0]})
    assert "systolic" not in {c.key for c in r["comparisons"]}


def test_satu_desimal_untuk_minuman_manis():
    days = [day(f"2026-10-0{i}", 5.0, sweet=1.0) for i in range(1, 4)] + [day(f"2026-10-1{i}", 8.0, sweet=0.0) for i in range(3)]
    sweet = next(c for c in compare_by_sleep(days)["comparisons"] if c.key == "sweet_drinks")
    assert (sweet.short_avg, sweet.other_avg) == (1.0, 0.0)
