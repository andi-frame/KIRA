import httpx
import pytest

from app.schemas.extraction import Extraction
from app.services import llm
from app.services.extraction import ExtractionError, extract_from_image, extract_from_text
from app.services.stt import OpenAICompatibleStt, SttError
from tests.graph.fakes import FakeExtractModel

RAKA_JSON = {
    "items": [{"name": "rendang", "portion_text": "1 potong", "portion_g_guess": 70, "meal_time": "lunch"}],
    "drinks": [{"name": "es teh manis", "size": "gelas", "count": 1}],
    "sleep": {"bed_time": "02:00", "wake_time": "07:00"},
    "activity": [],
    "clinical_result": None,
    "intent": "log",
}


@pytest.fixture(autouse=True)
def _reset_models():
    yield
    llm.set_models_for_tests(None, None)


async def test_text_extraction_maps_to_schema():
    llm.set_models_for_tests(None, FakeExtractModel(RAKA_JSON))
    result = await extract_from_text("tadi siang nasi padang rendang, es teh manis, begadang sampai jam 2")
    assert isinstance(result, Extraction)
    assert result.items[0].name == "rendang"
    assert result.drinks[0].name == "es teh manis"
    assert result.sleep.bed_time == "02:00"
    assert result.intent == "log"


async def test_schema_violation_becomes_extraction_error():
    llm.set_models_for_tests(None, FakeExtractModel({**RAKA_JSON, "intent": "bogus"}))
    with pytest.raises(ExtractionError):
        await extract_from_text("apa saja")


async def test_bad_time_format_is_a_schema_violation():
    bad = {**RAKA_JSON, "sleep": {"bed_time": "dua pagi", "wake_time": "07:00"}}
    llm.set_models_for_tests(None, FakeExtractModel(bad))
    with pytest.raises(ExtractionError):
        await extract_from_text("tidur jam dua pagi")


async def test_model_failure_becomes_extraction_error():
    llm.set_models_for_tests(None, FakeExtractModel(error=TimeoutError("boom")))
    with pytest.raises(ExtractionError):
        await extract_from_text("makan siang")


async def test_blank_text_rejected_before_calling_model():
    fake = FakeExtractModel(RAKA_JSON)
    llm.set_models_for_tests(None, fake)
    with pytest.raises(ValueError):
        await extract_from_text("   ")
    assert fake.calls == []


async def test_image_extraction_sends_the_image_and_kind():
    fake = FakeExtractModel(RAKA_JSON)
    llm.set_models_for_tests(None, fake)
    png = b"\x89PNG\r\n\x1a\n" + b"0" * 16
    result = await extract_from_image(png, "receipt")
    assert result.items
    content = fake.calls[0][-1].content
    assert any(part.get("type") == "image_url" and "image/png" in part["image_url"]["url"] for part in content)


def _stt(handler) -> OpenAICompatibleStt:
    return OpenAICompatibleStt(
        base_url="http://stt.test/v1", api_key="k", model="whisper", transport=httpx.MockTransport(handler)
    )


async def test_stt_returns_transcript():
    def handler(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/v1/audio/transcriptions"
        return httpx.Response(200, json={"text": "  tadi makan nasi padang  "})

    assert await _stt(handler).transcribe(b"audio", "v.m4a") == "tadi makan nasi padang"


async def test_stt_server_error_raises_stt_error():
    with pytest.raises(SttError):
        await _stt(lambda r: httpx.Response(500, text="oops")).transcribe(b"audio", "v.m4a")


async def test_stt_network_failure_raises_stt_error():
    def handler(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("down")

    with pytest.raises(SttError):
        await _stt(handler).transcribe(b"audio", "v.m4a")
