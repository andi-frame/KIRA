import pytest

from app.core_calc.foodindex import IndexEntry, best_match, build_index, normalize, search
from tests.core_calc.seed_data import seed_foods


@pytest.fixture(scope="module")
def index():
    return build_index([IndexEntry(f.id, label) for f in seed_foods().values() for label in [f.name, *f.aliases]])


def test_normalisasi_huruf_kecil_tanpa_tanda_baca():
    assert normalize("  Nasi-Uduk,  KOMPLIT! ") == "nasi uduk komplit"


def test_nama_persis_skor_satu(index):
    assert search("nasi uduk", index, top_k=1)[0].key == "nasi_uduk"
    assert search("nasi uduk", index, top_k=1)[0].score == pytest.approx(1.0)


def test_nasi_uduk_tidak_jatuh_ke_sambal(index):
    # temuan embedding saraf: "nasi uduk" paling mirip "sambal"; indeks n-gram tidak boleh mengulanginya
    assert all(not h.key.startswith("sambal") for h in search("nasi uduk", index, top_k=3))


@pytest.mark.parametrize("typo,expected", [("timunn", "timun"), ("kerupk", "kerupuk"), ("sambel trasi", "sambal_terasi")])
def test_salah_ketik_yang_jelas_dicocokkan(index, typo, expected):
    assert best_match(typo, index).key == expected


@pytest.mark.parametrize("query", ["ayam geprek", "makanan aneh sekali", ""])
def test_ragu_atau_tidak_dikenal_abstain(index, query):
    assert best_match(query, index) is None  # hidangan bukan makanan tunggal; salah cocok lebih buruk dari tidak cocok


def test_selisih_tipis_dengan_kandidat_kedua_abstain():
    idx = build_index([IndexEntry("a", "teh manis panas"), IndexEntry("b", "teh manis dingin")])
    assert best_match("teh manis", idx, min_score=0.1) is None


def test_hasil_satu_per_key_dan_urutan_stabil(index):
    hits = search("teh manis", index, top_k=10)
    assert len({h.key for h in hits}) == len(hits)
    assert hits == search("teh manis", index, top_k=10)
    assert [h.score for h in hits] == sorted((h.score for h in hits), reverse=True)
