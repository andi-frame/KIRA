import json

import pytest
from sqlalchemy import text

from app.config import settings
from app.graph import kira_graph
from app.graph.kira_graph import run_kira_graph
from app.graph.nodes.output_guardrail import check_reply
from app.services import llm
from tests.graph.fakes import FakeChatModel, FakeExtractModel, ai

RAKA = {
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


def install(chat_responses, extract_result=None, extract_error=None):
    chat = FakeChatModel(responses=chat_responses)
    extract = FakeExtractModel(extract_result, extract_error)
    llm.set_models_for_tests(chat, extract)
    return chat, extract


async def count(session_maker, table):
    async with session_maker() as session:
        return (await session.execute(text(f"select count(*) from {table}"))).scalar_one()


async def run(uid, sm, **kw):
    return await run_kira_graph(str(uid), "app", session_factory=sm, **kw)


async def test_red_flag_text_never_reaches_any_model(session_maker, make_user):
    uid = await make_user()
    chat, extract = install([ai("seharusnya tidak dipakai")], RAKA)
    result = await run(uid, session_maker, input_text="aku nyeri dada dan sesak napas")
    assert result.red_flag == "symptom"
    assert "IGD" in result.reply
    assert chat.call_count == 0 and extract.calls == []


async def test_dangerous_glucose_read_from_photo_triggers_emergency(session_maker, make_user):
    uid = await make_user()
    result_json = {**RAKA, "items": [], "drinks": [], "sleep": None, "intent": "result_input",
                   "clinical_result": {"kind": "fasting_glucose", "value": {"mg_dl": 45}}}
    chat, _ = install([ai("tidak dipakai")], result_json)
    result = await run(uid, session_maker, image=b"\xff\xd8\xff" + b"0" * 10, image_kind="result")
    assert result.red_flag == "glucose_low"
    assert chat.call_count == 0
    assert await count(session_maker, "clinical_results") == 0


async def test_checkin_saves_logs_with_nutrition_from_food_table(session_maker, make_user):
    uid = await make_user()
    install([ai("Sip, sudah kucatat ya.")], RAKA)
    result = await run(uid, session_maker, input_text="tadi siang rendang, es teh manis, begadang jam 2")
    assert result.reply == "Sip, sudah kucatat ya."
    assert result.extraction.items[0].name == "rendang"
    assert len(result.log_ids) == 3  # meal, drink, sleep
    async with session_maker() as session:
        rendang_fat = (await session.execute(
            text("select fat_g from log_items where name = 'rendang'"))).scalar_one()
        tea_sugar = (await session.execute(
            text("select sugar_g from log_items where name = 'es teh manis'"))).scalar_one()
    assert rendang_fat == pytest.approx(7.9 * 0.7)  # TKPI FP062, 70 g
    assert tea_sugar == pytest.approx(20.0)


async def test_tool_call_is_recorded_and_result_returned(session_maker, make_user):
    uid = await make_user()
    install(
        [ai(tool_calls=[{"name": "cari_gizi", "args": {"makanan": "rendang"}, "id": "c1"}]),
         ai("Satu potong rendang masih sesuai targetmu hari ini.")],
        {**RAKA, "items": [], "drinks": [], "sleep": None, "intent": "question_portion"},
    )
    result = await run(uid, session_maker, input_text="mau makan rendang malam ini, boleh berapa?")
    assert [c["name"] for c in result.tool_calls] == ["cari_gizi"]
    assert result.tool_calls[0]["result"]["found"] is True


async def test_unknown_food_flows_through_without_invented_numbers(session_maker, make_user):
    uid = await make_user()
    chat, _ = install(
        [ai(tool_calls=[{"name": "cari_gizi", "args": {"makanan": "xyzxyz"}, "id": "c1"}]),
         ai("Aku belum punya data makanan itu. Itu makanan apa ya?")],
        {**RAKA, "items": [], "drinks": [], "sleep": None, "intent": "question_portion"},
    )
    result = await run(uid, session_maker, input_text="boleh makan xyzxyz?")
    assert result.tool_calls[0]["result"] == {"found": False}
    assert not any(ch.isdigit() for ch in result.reply)


async def test_runaway_tool_loop_stops_at_recursion_limit(session_maker, make_user):
    uid = await make_user()
    install([ai(tool_calls=[{"name": "sisa_target_harian", "args": {}, "id": "loop"}])],
            {**RAKA, "items": [], "drinks": [], "sleep": None, "intent": "question_general"})
    result = await run(uid, session_maker, input_text="halo")
    assert "coba lagi" in result.reply.lower()


async def test_extraction_failure_gives_friendly_reply_and_saves_nothing(session_maker, make_user):
    uid = await make_user()
    chat, _ = install([ai("tidak dipakai")], extract_error=TimeoutError("down"))
    result = await run(uid, session_maker, input_text="tadi makan nasi goreng")
    assert "coba lagi" in result.reply.lower()
    assert chat.call_count == 0
    assert await count(session_maker, "logs") == 0


async def test_blank_input_is_rejected_before_any_model_call(session_maker, make_user):
    uid = await make_user()
    chat, extract = install([ai("x")], RAKA)
    with pytest.raises(ValueError):
        await run(uid, session_maker, input_text="   ")
    assert chat.call_count == 0 and extract.calls == []


async def test_user_and_assistant_messages_are_persisted(session_maker, make_user):
    uid = await make_user()
    install([ai("Halo juga!")], {**RAKA, "items": [], "drinks": [], "sleep": None, "intent": "question_general"})
    await run(uid, session_maker, input_text="halo")
    async with session_maker() as session:
        rows = (await session.execute(text("select role, content from messages order by created_at"))).all()
    assert [(r.role, r.content) for r in rows] == [("user", "halo"), ("assistant", "Halo juga!")]


async def test_demo_cache_short_circuits_models(session_maker, make_user, tmp_path, monkeypatch):
    uid = await make_user()
    cache = tmp_path / "demo_cache.json"
    cache.write_text(json.dumps({kira_graph.cache_key("halo kira"): "Balasan dari cache."}))
    monkeypatch.setattr(settings, "demo_cache", True)
    monkeypatch.setattr(kira_graph, "DEMO_CACHE_PATH", cache)
    chat, extract = install([ai("tidak dipakai")], RAKA)
    result = await run(uid, session_maker, input_text="Halo  KIRA")
    assert result.reply == "Balasan dari cache."
    assert chat.call_count == 0 and extract.calls == []


@pytest.mark.parametrize(
    "text_",
    ["Minum metformin 500 mg dua kali sehari ya", "Kamu menderita diabetes", "Hentikan obat tensimu",
     "Dosis insulin yang pas untukmu 10 unit", "Kamu aman, makan saja sepuasnya"],
)
def test_guardrail_rejects_medication_diagnosis_and_safe_claims(text_):
    ok, safe = check_reply(text_)
    assert ok is False and safe != text_ and "dokter" in safe.lower()


@pytest.mark.parametrize(
    "text_",
    ["Natrium dari rendang itu sekitar 420 mg, masih sesuai targetmu hari ini.",
     "Coba ganti es teh manis jadi tawar minggu ini.",
     "Kalau ada obat dari dokter, ikuti arahannya ya."],
)
def test_guardrail_allows_normal_lifestyle_replies(text_):
    assert check_reply(text_) == (True, text_)


async def test_demo_cache_entry_with_extraction_still_saves_logs_without_models(
    session_maker, make_user, tmp_path, monkeypatch
):
    uid = await make_user()
    cache = tmp_path / "demo_cache.json"
    cache.write_text(json.dumps({kira_graph.cache_key("check-in demo"): {"reply": "Sudah kucatat.", "extraction": RAKA}}))
    monkeypatch.setattr(settings, "demo_cache", True)
    monkeypatch.setattr(kira_graph, "DEMO_CACHE_PATH", cache)
    chat, extract = install([ai("tidak dipakai")], RAKA)
    result = await run(uid, session_maker, input_text="check-in demo")
    assert result.reply == "Sudah kucatat."
    assert result.extraction.items[0].name == "rendang" and len(result.log_ids) == 3
    assert chat.call_count == 0 and extract.calls == []
    assert await count(session_maker, "logs") == 3


async def test_demo_cache_never_bypasses_red_flag_check(session_maker, make_user, tmp_path, monkeypatch):
    uid = await make_user()
    cache = tmp_path / "demo_cache.json"
    cache.write_text(json.dumps({kira_graph.cache_key("nyeri dada"): "Balasan cache yang salah."}))
    monkeypatch.setattr(settings, "demo_cache", True)
    monkeypatch.setattr(kira_graph, "DEMO_CACHE_PATH", cache)
    install([ai("x")], RAKA)
    result = await run(uid, session_maker, input_text="nyeri dada")
    assert result.red_flag == "symptom" and "IGD" in result.reply


async def test_shipped_demo_cache_covers_every_scripted_input():
    from seed.build_demo_cache import DEMO_ENTRIES

    shipped = json.loads(kira_graph.DEMO_CACHE_PATH.read_text(encoding="utf-8"))
    for scripted in DEMO_ENTRIES:
        assert kira_graph.cache_key(scripted) in shipped, scripted


@pytest.mark.parametrize(
    "text_",
    [
        "Coba glimepiride 2 mg ya",
        "Minum obat gula 500mg setelah makan",
        "Sepertinya kamu sudah kena diabetes",
        "Kamu punya diabetes tipe 2",
        "Gulamu 180, itu tergolong diabetes",
        "Rendang masih aman kok buat kamu",
        "Aman, makan saja",
    ],
)
def test_guardrail_catches_more_drug_diagnosis_and_safe_phrasings(text_):
    ok, safe = check_reply(text_)
    assert ok is False and "dokter" in safe.lower(), text_


@pytest.mark.parametrize(
    "text_",
    [
        "Kalau kamu punya riwayat diabetes di keluarga, cek gula darah ya.",
        "Natrium rendang itu sekitar 420 mg, minum air putih setelahnya.",
        "Ini belum tentu aman kalau kamu lanjut begadang, tidur lebih awal ya.",
    ],
)
def test_guardrail_still_allows_ordinary_lifestyle_replies(text_):
    assert check_reply(text_) == (True, text_)


async def test_agent_failure_after_logs_saved_says_so_instead_of_asking_to_resend(session_maker, make_user):
    uid = await make_user()
    chat = FakeChatModel(responses=[ai("x")], fail_with=TimeoutError("llm down"))
    llm.set_models_for_tests(chat, FakeExtractModel(RAKA))
    result = await run(uid, session_maker, input_text="tadi rendang, es teh manis, tidur jam 2")
    assert len(result.log_ids) == 3
    assert result.extraction is not None
    assert "sudah kucatat" in result.reply.lower()
    assert "tidak perlu" in result.reply.lower()
    assert await count(session_maker, "logs") == 3


async def test_clinical_numbers_in_a_question_are_not_saved_as_results(session_maker, make_user):
    uid = await make_user()
    hypothetical = {**RAKA, "items": [], "drinks": [], "sleep": None, "intent": "question_general",
                    "clinical_result": {"kind": "fasting_glucose", "value": {"mg_dl": 130}}}
    install([ai("Itu sebaiknya dikonfirmasi lewat pemeriksaan ya.")], hypothetical)
    await run(uid, session_maker, input_text="kalau gula puasaku 130 itu gimana?")
    assert await count(session_maker, "clinical_results") == 0


async def test_balasan_melanggar_ditulis_ulang_sekali_bukan_langsung_diganti_kalimat_baku(session_maker, make_user):
    uid = await make_user()
    chat, _ = install([ai("Porsi segitu aman kok, makan saja."), ai("Porsi segitu masih sesuai targetmu hari ini.")], RAKA)
    result = await run(uid, session_maker, input_text="boleh makan rendang?")
    assert result.reply == "Porsi segitu masih sesuai targetmu hari ini."
    assert chat.call_count == 2


async def test_tetap_melanggar_setelah_ditulis_ulang_diganti_kalimat_baku(session_maker, make_user):
    uid = await make_user()
    chat, _ = install([ai("Aman kok."), ai("Pokoknya aman, makan sepuasnya.")], RAKA)
    result = await run(uid, session_maker, input_text="boleh makan rendang?")
    assert "dokter" in result.reply.lower() and "aman kok" not in result.reply.lower()
    assert chat.call_count == 2  # tepat satu kali kesempatan menulis ulang, tidak berputar terus


async def test_balasan_bersih_tidak_memicu_penulisan_ulang(session_maker, make_user):
    uid = await make_user()
    chat, _ = install([ai("Masih sesuai targetmu hari ini.")], RAKA)
    result = await run(uid, session_maker, input_text="boleh makan rendang?")
    assert result.reply == "Masih sesuai targetmu hari ini." and chat.call_count == 1


def test_markdown_dibersihkan_agar_tidak_tampil_sebagai_tanda_bintang_mentah():
    from app.graph.nodes.output_guardrail import strip_markdown

    raw = "## Ringkasan\nSudah dicatat, **cukup 1 porsi** ya.\n\n* Kalori: *sekitar* 135 kkal\n* Lemak: `5,5` g\n\n\n\nSemoga membantu."
    assert strip_markdown(raw) == "Ringkasan\nSudah dicatat, cukup 1 porsi ya.\n\n- Kalori: sekitar 135 kkal\n- Lemak: 5,5 g\n\nSemoga membantu."
    assert strip_markdown("Teks biasa 2 * 3 = 6 dan snake_case tetap utuh.") == "Teks biasa 2 * 3 = 6 dan snake_case tetap utuh."
    assert strip_markdown("") == ""


async def test_balasan_akhir_sudah_bersih_dari_markdown(session_maker, make_user):
    uid = await make_user()
    install([ai("Boleh, **1 potong** saja ya.")], RAKA)
    result = await run(uid, session_maker, input_text="boleh makan rendang?")
    assert result.reply == "Boleh, 1 potong saja ya."
