from app.schemas.extraction import Extraction
from seed.eval_extraction import CASES, Case, score_case, summarize


def _case(**kw) -> Case:
    return Case(text="x", **kw)


def test_semua_yang_diharapkan_terambil_skor_penuh():
    result = Extraction.model_validate(
        {
            "items": [{"name": "nasi goreng"}],
            "drinks": [{"name": "es teh manis"}],
            "sleep": {"bed_time": "02:00"},
            "intent": "log",
        }
    )
    case = _case(foods=["nasi goreng"], drinks=["teh"], bed_time="02:00", intent="log")
    score = score_case(case, result)
    assert score.hits == score.total == 4


def test_item_yang_tidak_terambil_mengurangi_skor_dan_dicatat():
    result = Extraction.model_validate({"items": [{"name": "nasi"}], "intent": "log"})
    score = score_case(_case(foods=["nasi", "rendang"], intent="log"), result)
    assert (score.hits, score.total) == (2, 3)
    assert score.missed == ["rendang"]


def test_pencocokan_tidak_peduli_huruf_besar():
    result = Extraction.model_validate({"drinks": [{"name": "Kopi Susu"}], "intent": "log"})
    assert score_case(_case(drinks=["kopi susu"], intent="log"), result).hits == 2


def test_jam_tidur_harus_sama_persis():
    result = Extraction.model_validate({"sleep": {"bed_time": "01:00"}, "intent": "log"})
    score = score_case(_case(bed_time="02:00", intent="log"), result)
    assert score.missed == ["tidur 02:00"]


def test_ringkasan_menghitung_persentase_dan_kegagalan_ekstraksi():
    perfect = Extraction.model_validate({"items": [{"name": "nasi"}], "intent": "log"})
    scores = [score_case(_case(foods=["nasi"], intent="log"), perfect), None]
    summary = summarize(scores)
    assert summary["cases"] == 2 and summary["failed"] == 1
    assert summary["hit_rate"] == 1.0


def test_kumpulan_kasus_cukup_beragam():
    assert len(CASES) >= 20
    assert any(c.intent == "question_portion" for c in CASES)
    assert any(c.bed_time for c in CASES)
