import pytest

from app.core_calc.goals import GOAL_KINDS, current_value, evaluate, validate_target


def day(logged=True, active=None, sweet=None, sleep=None) -> dict:
    return {"logged": logged, "active_minutes": active, "sweet_drinks": sweet, "sleep_hours": sleep}


def test_aktif_menjumlah_menit_dan_hari_tanpa_catatan_tidak_dihitung_nol_palsu():
    week = [day(active=40), day(active=35.5), day(logged=False), day(active=0)]
    assert current_value("active_minutes_week", week) == 75.5


def test_target_minimum_tercapai_saat_sama_atau_lebih():
    week = [day(active=75), day(active=75)]
    p = evaluate("active_minutes_week", 150, week)
    assert p.met and p.status == "met" and p.remaining == 0 and p.fraction == 1.0
    q = evaluate("active_minutes_week", 151, week)
    assert not q.met and q.status == "in_progress" and q.remaining == 1


def test_target_maksimum_minuman_manis_melewati_batas_berarti_over():
    week = [day(sweet=3), day(sweet=4), day(sweet=2)]
    ok = evaluate("sweet_drinks_week", 9, week)
    assert ok.met and ok.status == "within" and ok.remaining == 0
    over = evaluate("sweet_drinks_week", 7, week)
    assert not over.met and over.status == "over" and over.current == 9
    exact = evaluate("sweet_drinks_week", 9, week)
    assert exact.status == "within"  # tepat di batas masih sesuai


def test_malam_tidur_cukup_menghitung_malam_dengan_minimal_tujuh_jam():
    week = [day(sleep=7.0), day(sleep=6.9), day(sleep=8.5), day(sleep=None), day(sleep=5)]
    assert current_value("sleep_nights", week) == 2


def test_hari_mencatat_menghitung_hari_yang_ada_catatan():
    assert current_value("logging_days", [day(), day(logged=False), day(), day()]) == 3


def test_fraction_dibatasi_nol_sampai_satu_dan_target_maks_nol_ditangani():
    assert evaluate("active_minutes_week", 100, [day(active=250)]).fraction == 1.0
    assert evaluate("active_minutes_week", 100, [day(active=25)]).fraction == 0.25
    zero_ok = evaluate("sweet_drinks_week", 0, [day(sweet=0)])
    zero_bad = evaluate("sweet_drinks_week", 0, [day(sweet=1)])
    assert zero_ok.fraction == 1.0 and zero_ok.met
    assert zero_bad.fraction == 0.0 and not zero_bad.met


def test_minggu_kosong_tidak_error():
    for kind in GOAL_KINDS:
        p = evaluate(kind, GOAL_KINDS[kind]["default"], [])
        assert p.current == 0


@pytest.mark.parametrize("kind,target", [("active_minutes_week", 150), ("sleep_nights", 7), ("sweet_drinks_week", 0)])
def test_target_dalam_rentang_diterima(kind, target):
    assert validate_target(kind, target) == target


@pytest.mark.parametrize("kind,target", [("active_minutes_week", 10), ("sleep_nights", 8), ("sweet_drinks_week", -1), ("logging_days", 0)])
def test_target_di_luar_rentang_ditolak(kind, target):
    with pytest.raises(ValueError):
        validate_target(kind, target)


def test_jenis_tidak_dikenal_ditolak():
    with pytest.raises(ValueError):
        validate_target("langkah", 1000)
