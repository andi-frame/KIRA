import base64
from datetime import datetime, timezone

import pytest
from sqlalchemy import text

from app.config import settings
from app.repos import logs as logs_repo
from app.services import llm, stt
from app.services.jobs import enqueue_reminders
from app.services.whatsapp import shorten
from tests.api.helpers import FakeStt, install_models, reset_models
from tests.graph.fakes import FakeChatModel, FakeExtractModel, ai

SECRET = {"X-Bot-Secret": "s3cret"}
JID = "6281200000001@s.whatsapp.net"
QUESTION = {"items": [], "drinks": [], "sleep": None, "activity": [], "clinical_result": None,
            "intent": "question_general"}


@pytest.fixture(autouse=True)
def _bot(monkeypatch):
    monkeypatch.setattr(settings, "bot_secret", "s3cret")
    yield
    reset_models()


async def link(client, headers, jid=JID):
    code = (await client.post("/whatsapp/link-code", headers=headers)).json()["code"]
    return await client.post("/webhooks/whatsapp", headers=SECRET, json={"jid": jid, "text": code})


async def say(client, text_, jid=JID, **extra):
    r = await client.post("/webhooks/whatsapp", headers=SECRET, json={"jid": jid, "text": text_, **extra})
    assert r.status_code == 200, r.text
    return r.json()["reply"]


async def test_webhook_needs_the_shared_secret(client):
    body = {"jid": JID, "text": "halo"}
    assert (await client.post("/webhooks/whatsapp", json=body)).status_code == 401
    assert (await client.post("/webhooks/whatsapp", json=body, headers={"X-Bot-Secret": "salah"})).status_code == 401


async def test_webhook_is_disabled_when_no_secret_is_configured(client, monkeypatch):
    monkeypatch.setattr(settings, "bot_secret", "")
    r = await client.post("/webhooks/whatsapp", json={"jid": JID, "text": "halo"}, headers={"X-Bot-Secret": ""})
    assert r.status_code == 503


async def test_unlinked_numbers_get_instructions_and_never_reach_a_model(client):
    chat, extract = install_models()
    reply = await say(client, "tadi makan nasi goreng")
    assert "belum tertaut" in reply.lower() and "KIRA" in reply
    assert chat.call_count == 0 and extract.calls == []


async def test_link_code_ties_the_number_to_the_account(client, auth_headers):
    code_resp = await client.post("/whatsapp/link-code", headers=auth_headers)
    assert code_resp.status_code == 200
    code = code_resp.json()["code"]
    assert code.startswith("KIRA ") and len(code) == len("KIRA 1234")
    reply = await say(client, code.lower())  # huruf kecil pun diterima
    assert "tertaut" in reply.lower()
    again = await say(client, code)
    assert "belum tertaut" in again.lower() or "kedaluwarsa" in again.lower()  # kode sekali pakai


async def test_wrong_code_does_not_link(client, auth_headers):
    await client.post("/whatsapp/link-code", headers=auth_headers)
    reply = await say(client, "KIRA 0000")
    assert "belum tertaut" in reply.lower() or "tidak valid" in reply.lower()


async def test_linked_text_runs_the_same_graph_on_the_whatsapp_channel(client, auth_headers, engine):
    await link(client, auth_headers)
    install_models(reply="Halo juga! Aku KIRA.", extract=QUESTION)
    assert await say(client, "halo") == "Halo juga! Aku KIRA."
    async with engine.connect() as conn:
        channels = (await conn.execute(text("select distinct channel from messages"))).scalars().all()
    assert channels == ["whatsapp"]


async def test_danger_words_over_whatsapp_get_the_emergency_reply_without_models(client, auth_headers):
    await link(client, auth_headers)
    chat, _ = install_models()
    reply = await say(client, "sakit dada dari tadi")
    assert "IGD" in reply and chat.call_count == 0


async def test_voice_notes_are_transcribed_first(client, auth_headers):
    await link(client, auth_headers)
    install_models(reply="Sudah kucatat.", extract=QUESTION)
    fake = FakeStt("tadi makan rendang")
    stt.set_stt_for_tests(fake)
    audio = base64.b64encode(b"opus-bytes").decode()
    reply = await say(client, None, media_type="audio", media=audio)
    assert fake.calls == 1 and reply == "Sudah kucatat."


async def test_photo_kind_comes_from_the_caption(client, auth_headers):
    await link(client, auth_headers)
    _, extract = install_models(reply="Struknya terbaca.", extract=QUESTION)
    png = base64.b64encode(b"\x89PNG\r\n\x1a\n" + b"0" * 16).decode()
    await say(client, "struk indomaret", media_type="image", media=png)
    system_prompt = extract.calls[0][0].content
    assert "struk belanja" in system_prompt


def test_replies_are_shortened_for_chat():
    long = "Kalimat satu. Kalimat dua. Kalimat tiga. Kalimat empat. Kalimat lima. Kalimat enam."
    assert shorten(long) == "Kalimat satu. Kalimat dua. Kalimat tiga. Kalimat empat."
    assert shorten("Pendek saja.") == "Pendek saja."
    assert len(shorten("x" * 5000)) <= 900


async def test_reminders_go_to_linked_users_without_a_checkin_today_once_a_day(client, auth_headers, session_maker, engine):
    await link(client, auth_headers)
    async with session_maker() as s:
        assert await enqueue_reminders(s) == 1
        assert await enqueue_reminders(s) == 0  # satu pengingat per hari
    pending = (await client.get("/webhooks/whatsapp/outbox", headers=SECRET)).json()["messages"]
    assert len(pending) == 1 and pending[0]["jid"] == JID and "check-in" in pending[0]["text"].lower()
    assert (await client.post(f"/webhooks/whatsapp/outbox/{pending[0]['id']}/ack", headers=SECRET)).status_code == 200
    assert (await client.get("/webhooks/whatsapp/outbox", headers=SECRET)).json()["messages"] == []


async def test_no_reminder_when_the_user_already_checked_in_today(client, auth_headers, session_maker, make_user):
    await link(client, auth_headers)
    async with session_maker() as s:
        uid = (await s.execute(text("select id from users limit 1"))).scalar_one()
        await logs_repo.add_log(s, uid, kind="sleep", source="text", occurred_at=datetime.now(timezone.utc),
                                extracted={"hours": 6}, raw_text="x", items=[])
        assert await enqueue_reminders(s) == 0


async def test_stop_pengingat_mematikan_kanal_tanpa_llm_dan_bisa_dinyalakan_lagi(client, auth_headers):
    await link(client, auth_headers)
    await client.put("/plan/preferences", json={"channels": {"whatsapp": True}}, headers=auth_headers)
    chat = FakeChatModel(responses=[ai("tidak dipakai")])
    extract = FakeExtractModel(QUESTION)
    llm.set_models_for_tests(chat, extract)

    reply = await say(client, "Stop pengingat")
    assert "dimatikan" in reply and chat.call_count == 0 and extract.calls == []
    prefs = (await client.get("/plan/preferences", headers=auth_headers)).json()
    assert prefs["channels"]["whatsapp"] is False

    assert "dinyalakan" in await say(client, "nyalakan pengingat")
    assert (await client.get("/plan/preferences", headers=auth_headers)).json()["channels"]["whatsapp"] is True


async def test_pertanyaan_rencana_lewat_whatsapp_memakai_tool_rencana(client, auth_headers):
    await link(client, auth_headers)
    chat = FakeChatModel(responses=[ai("Usulan hari ini sudah kusiapkan.")])
    llm.set_models_for_tests(chat, FakeExtractModel(QUESTION))
    await say(client, "rencana makan hari ini apa?")
    tools = [m for m in chat.seen[0] if type(m).__name__ == "ToolMessage"]
    assert [t.name for t in tools] == ["rencana_hari_ini"]  # disiapkan sebelum model, bukan dikarang
