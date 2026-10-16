import pytest

from app.services import stt
from app.services.stt import SttError
from tests.api.helpers import FakeStt, install_models, reset_models


@pytest.fixture(autouse=True)
def _cleanup():
    yield
    reset_models()


async def test_message_returns_reply_extraction_and_log_ids(client, auth_headers):
    install_models()
    r = await client.post("/chat/message", json={"text": "tadi siang rendang, es teh manis"}, headers=auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["reply"] == "Sip, sudah kucatat."
    assert body["extraction"]["items"][0]["name"] == "rendang"
    assert len(body["log_ids"]) == 3 and body["red_flag"] is None


@pytest.mark.parametrize("payload", [{"text": ""}, {"text": "   "}, {}])
async def test_blank_message_is_422_and_never_calls_a_model(client, auth_headers, payload):
    chat, ext = install_models()
    r = await client.post("/chat/message", json=payload, headers=auth_headers)
    assert r.status_code == 422
    assert chat.call_count == 0 and ext.calls == []


async def test_message_requires_login(client):
    assert (await client.post("/chat/message", json={"text": "halo"})).status_code == 401


async def test_red_flag_message_returns_emergency_reply(client, auth_headers):
    chat, _ = install_models()
    r = await client.post("/chat/message", json={"text": "nyeri dada hebat"}, headers=auth_headers)
    assert r.json()["red_flag"] == "symptom" and "IGD" in r.json()["reply"]
    assert chat.call_count == 0


async def test_voice_is_transcribed_then_processed(client, auth_headers):
    install_models()
    fake = FakeStt("tadi makan rendang")
    stt.set_stt_for_tests(fake)
    r = await client.post("/chat/voice", files={"audio": ("v.m4a", b"123", "audio/mp4")}, headers=auth_headers)
    assert r.status_code == 200 and fake.calls == 1
    assert r.json()["transcript"] == "tadi makan rendang"


async def test_stt_failure_is_502_with_friendly_message_and_saves_nothing(client, auth_headers, engine):
    install_models()
    stt.set_stt_for_tests(FakeStt(error=SttError("down")))
    r = await client.post("/chat/voice", files={"audio": ("v.m4a", b"123", "audio/mp4")}, headers=auth_headers)
    assert r.status_code == 502 and "coba lagi" in r.json()["detail"].lower()
    from sqlalchemy import text
    async with engine.connect() as conn:
        assert (await conn.execute(text("select count(*) from logs"))).scalar_one() == 0


async def test_silent_audio_is_422(client, auth_headers):
    install_models()
    stt.set_stt_for_tests(FakeStt(""))
    r = await client.post("/chat/voice", files={"audio": ("v.m4a", b"123", "audio/mp4")}, headers=auth_headers)
    assert r.status_code == 422


async def test_photo_flow_and_validation(client, auth_headers):
    install_models()
    png = b"\x89PNG\r\n\x1a\n" + b"0" * 32
    ok = await client.post("/chat/photo?kind=receipt", files={"image": ("s.png", png, "image/png")}, headers=auth_headers)
    assert ok.status_code == 200 and ok.json()["extraction"]["items"]
    bad_kind = await client.post("/chat/photo?kind=selfie", files={"image": ("s.png", png, "image/png")}, headers=auth_headers)
    assert bad_kind.status_code == 422
    empty = await client.post("/chat/photo?kind=food", files={"image": ("s.png", b"", "image/png")}, headers=auth_headers)
    assert empty.status_code == 422
    huge = await client.post("/chat/photo?kind=food", files={"image": ("s.jpg", b"0" * (9 * 1024 * 1024), "image/jpeg")}, headers=auth_headers)
    assert huge.status_code == 413


async def test_silence_hallucination_never_reaches_chat_models(client, auth_headers, engine):
    import httpx
    from sqlalchemy import text

    chat, ext = install_models()
    stt.set_stt_for_tests(stt.OpenAICompatibleStt(
        "https://stt.test/v1", "test", "whisper-large-v3-turbo",
        transport=httpx.MockTransport(lambda request: httpx.Response(200, json={
            "text": "Terima kasih.",
            "segments": [{"text": "Terima kasih.", "no_speech_prob": 0.98, "avg_logprob": -1.5}],
        })),
    ))
    r = await client.post("/chat/voice", files={"audio": ("v.m4a", b"audio", "audio/mp4")}, headers=auth_headers)
    assert r.status_code == 422
    assert "tidak terdengar jelas" in r.json()["detail"]
    assert chat.call_count == 0 and ext.calls == []
    async with engine.connect() as conn:
        assert (await conn.execute(text("select count(*) from messages"))).scalar_one() == 0
        assert (await conn.execute(text("select count(*) from logs"))).scalar_one() == 0
