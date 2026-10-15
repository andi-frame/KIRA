import pytest

from app.core_calc.triage import glucose_range, hba1c_range, trend_label, triage_flags


@pytest.mark.parametrize(
    "kind,value,expected",
    [
        ("fasting_glucose", 95, "normal"),
        ("fasting_glucose", 100, "prediabetes"),
        ("fasting_glucose", 125, "prediabetes"),
        ("fasting_glucose", 126, "diabetes_range"),
        ("random_glucose", 199, "below_cutoff"),
        ("random_glucose", 200, "diabetes_range"),
    ],
)
def test_rentang_glukosa_mengikuti_perkeni(kind, value, expected):
    assert glucose_range(kind, value) == expected


@pytest.mark.parametrize("pct,expected", [(5.6, "normal"), (5.7, "prediabetes"), (6.4, "prediabetes"), (6.5, "diabetes_range")])
def test_rentang_hba1c(pct, expected):
    assert hba1c_range(pct) == expected


def test_tren_butuh_minimal_dua_titik_dan_melewati_derau():
    assert trend_label("sys", [130]) is None
    assert trend_label("sys", [130, 133]) == "stabil"  # selisih 3 < 5 mmHg
    assert trend_label("sys", [130, 138]) == "naik"
    assert trend_label("fasting_glucose", [120, 100]) == "turun"
    assert trend_label("hba1c", [5.8, 5.9]) == "stabil"
    assert trend_label("hba1c", [5.8, 6.3]) == "naik"


def levels(flags):
    return [f["level"] for f in flags]


def test_tanpa_hasil_apa_pun_hanya_ada_catatan_info():
    flags = triage_flags({}, None)
    assert levels(flags) == ["info"] and "belum ada hasil" in flags[0]["text"].lower()


def test_hipertensi_dan_gula_diabetes_menjadi_perhatian_dengan_bahasa_bukan_diagnosis():
    flags = triage_flags({"blood_pressure": (150, 95), "fasting_glucose": 130}, None)
    assert levels(flags) == ["perhatian", "perhatian"]
    text = " ".join(f["text"] for f in flags).lower()
    assert "150/95" in text and "bukan diagnosis" in text
    assert "menderita" not in text and "pasti" not in text


def test_rentang_prediabetes_dan_normal_tinggi_hanya_dipantau():
    flags = triage_flags({"blood_pressure": (132, 86), "hba1c": 6.0}, None)
    assert levels(flags) == ["pantau", "pantau"]


def test_nilai_normal_tidak_menghasilkan_penanda_selain_data_lengkap():
    flags = triage_flags({"blood_pressure": (118, 76), "fasting_glucose": 90}, "low")
    assert flags == []


def test_skrining_findrisc_tinggi_dipantau_dan_diurutkan_setelah_perhatian():
    flags = triage_flags({"fasting_glucose": 130}, "high")
    assert levels(flags) == ["perhatian", "pantau"]


def test_glukosa_sewaktu_di_bawah_200_tidak_diberi_penanda():
    assert triage_flags({"random_glucose": 150}, None) == []
