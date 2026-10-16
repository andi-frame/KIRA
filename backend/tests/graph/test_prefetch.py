import pytest

from app.graph.nodes.prefetch_tools import MAX_FOODS, plan_calls
from tests.graph.test_graph import RAKA, install, run

QUESTION = {"items": [{"name": "rendang"}], "drinks": [], "sleep": None, "activity": [], "clinical_result": None,
            "intent": "question_portion"}


def names(calls):
    return [n for n, _ in calls]


def test_mencatat_makan_dan_minum_menyiapkan_gizi_tiap_item_dan_sisa_target():
    calls = plan_calls(RAKA)
    assert names(calls) == ["cari_gizi", "cari_gizi", "sisa_target_harian"]
    assert calls[0][1] == {"makanan": "rendang", "porsi_gram": 70}  # porsi tebakan ikut, seperti yang akan diminta agent
    assert calls[1][1] == {"makanan": "es teh manis"}


def test_pertanyaan_porsi_menyiapkan_gizi_porsi_bawaan_dan_sisa_target():
    calls = plan_calls({**QUESTION, "items": [{"name": "rendang", "portion_g_guess": 200}]})
    assert calls == [("cari_gizi", {"makanan": "rendang"}), ("sisa_target_harian", {})]  # pertanyaan: porsi bawaan, bukan tebakan


def test_pertanyaan_porsi_tanpa_nama_makanan_tetap_menyiapkan_sisa_target():
    assert plan_calls({**QUESTION, "items": []}) == [("sisa_target_harian", {})]


def test_hasil_pemeriksaan_menyiapkan_risiko_terbaru():
    extraction = {"items": [], "drinks": [], "intent": "result_input", "clinical_result": {"kind": "blood_pressure", "value": {"sys": 130, "dia": 85}}}
    assert plan_calls(extraction) == [("hitung_risiko", {})]


@pytest.mark.parametrize("extraction", [None, {}, {"intent": "question_general", "items": [{"name": "x"}]},
                                        {"intent": "log", "items": [], "drinks": []}])
def test_tanpa_kebutuhan_pasti_tidak_ada_tool_disiapkan(extraction):
    assert plan_calls(extraction) == []  # agent tetap bebas memanggil tool sendiri


def test_nama_ganda_dikosongkan_dan_dibatasi():
    items = [{"name": "Rendang"}, {"name": "rendang"}, {"name": " "}] + [{"name": f"makanan {i}"} for i in range(10)]
    calls = plan_calls({"intent": "log", "items": items, "drinks": []})
    foods = [a["makanan"] for n, a in calls if n == "cari_gizi"]
    assert len(foods) == MAX_FOODS and foods[0] == "Rendang" and len(set(f.lower() for f in foods)) == MAX_FOODS


async def test_graf_menjawab_dengan_satu_panggilan_model_dan_hasil_tool_sudah_ada(session_maker, make_user):
    uid = await make_user()
    chat, _ = install([__import__("tests.graph.fakes", fromlist=["ai"]).ai("Tercatat ya.")], RAKA)
    result = await run(uid, session_maker, input_text="tadi siang rendang dan es teh manis")
    assert chat.call_count == 1  # sebelumnya dua: satu untuk meminta tool, satu untuk menjawab
    assert result.reply == "Tercatat ya."
    # model melihat pasangan panggilan tool + hasilnya, dengan angka dari kode
    seen = chat.seen[0]
    kinds = [type(m).__name__ for m in seen]
    assert kinds.count("ToolMessage") == 3 and "AIMessage" in kinds
    tool_text = " ".join(str(m.content) for m in seen if type(m).__name__ == "ToolMessage")
    assert '"found": true' in tool_text and "sumber" in tool_text and "limits" in tool_text
    # jejak "Lihat cara KIRA menghitung" tetap lengkap
    assert [c["name"] for c in result.tool_calls] == ["cari_gizi", "cari_gizi", "sisa_target_harian"]
    assert result.tool_calls[0]["result"]["found"] is True and result.tool_calls[2]["result"]["limits"]["sugar_g"] == 50


async def test_agent_tetap_boleh_memanggil_tool_lain_setelah_prefetch(session_maker, make_user):
    from tests.graph.fakes import ai

    uid = await make_user()
    chat, _ = install(
        [ai(tool_calls=[{"name": "hitung_risiko", "args": {}, "id": "r1"}]), ai("Rentang risikomu sedang.")], RAKA
    )
    result = await run(uid, session_maker, input_text="tadi siang rendang dan es teh manis, risikoku gimana?")
    assert chat.call_count == 2
    assert [c["name"] for c in result.tool_calls][-1] == "hitung_risiko"
    assert result.tool_calls[0]["name"] == "cari_gizi"


async def test_pesan_tanpa_catatan_tidak_menjalankan_tool_awal(session_maker, make_user):
    from tests.graph.fakes import ai

    uid = await make_user()
    chat, _ = install([ai("Halo juga!")], {**RAKA, "items": [], "drinks": [], "sleep": None, "intent": "question_general"})
    result = await run(uid, session_maker, input_text="halo")
    assert chat.call_count == 1 and result.tool_calls == []
    assert all(type(m).__name__ != "ToolMessage" for m in chat.seen[0])


@pytest.mark.parametrize("text_", ["kalau aku kurangi gorengan, risikoku berubah gimana?", "Resikoku 10 tahun lagi gimana",
                                   "kemungkinan aku kena diabetes berapa?"])
def test_pertanyaan_risiko_menyiapkan_hitung_risiko(text_):
    extraction = {"intent": "question_general", "items": [], "drinks": []}
    assert plan_calls(extraction, text=text_) == [("hitung_risiko", {})]


def test_hitung_risiko_tidak_disiapkan_dua_kali():
    extraction = {"items": [], "drinks": [], "intent": "result_input", "clinical_result": {"kind": "hba1c", "value": {"percent": 5.9}}}
    assert plan_calls(extraction, text="HbA1c 5,9, risikoku gimana?") == [("hitung_risiko", {})]


def test_pertanyaan_biasa_tanpa_kata_risiko_tidak_menyiapkan_hitung_risiko():
    assert plan_calls({"intent": "question_general", "items": [], "drinks": []}, text="halo KIRA, apa kabar?") == []


SLEEP_ONLY = {"items": [], "drinks": [], "sleep": {"bed_time": "02:00", "wake_time": "07:00"}, "activity": [],
              "clinical_result": None, "intent": "log"}


@pytest.mark.parametrize("extraction", [
    SLEEP_ONLY,
    {**SLEEP_ONLY, "sleep": None, "activity": [{"kind": "jalan kaki", "minutes": 30}]},
    # terukur pada model sungguhan: "semalam tidur cuma 5 jam" (tanpa jam tidur/bangun) terekstrak tanpa field sleep
    {**SLEEP_ONLY, "sleep": None, "summary": "Tidur 5 jam semalam"},
])
async def test_catatan_tidur_atau_aktivitas_saja_dijawab_tanpa_tool(session_maker, make_user, extraction):
    from tests.graph.fakes import ai

    uid = await make_user()
    chat, _ = install([ai("Tidurnya sudah kucatat ya.")], extraction)
    result = await run(uid, session_maker, input_text="semalam tidur cuma 5 jam")
    assert chat.call_count == 1 and chat.tools_bound == [False]  # model tidak bisa mencari gizi makanan dari riwayat
    assert result.reply == "Tidurnya sudah kucatat ya." and result.tool_calls == []


async def test_putaran_tool_dari_model_dibatasi_lalu_model_menjawab_tanpa_tool(session_maker, make_user):
    from app.graph.kira_graph import MAX_TOOL_ROUNDS
    from tests.graph.fakes import ai

    uid = await make_user()
    whatif = lambda i: ai(tool_calls=[{"name": "simulasi_whatif", "args": {"perubahan": {"active_30min": True}}, "id": f"w{i}"}])
    chat, _ = install([*[whatif(i) for i in range(MAX_TOOL_ROUNDS)], ai("Rentangnya bisa turun bila rutin bergerak.")],
                      {"items": [], "drinks": [], "intent": "question_general"})
    result = await run(uid, session_maker, input_text="kalau aku rajin jalan kaki gimana?")
    assert chat.call_count == MAX_TOOL_ROUNDS + 1
    assert chat.tools_bound == [True] * MAX_TOOL_ROUNDS + [False]
    # panggilan terakhir tanpa tool: hasil tool tetap terlihat sebagai teks, tanpa pesan tool mentah
    last = chat.seen[-1]
    assert all(type(m).__name__ != "ToolMessage" for m in last)
    assert any("simulasi_whatif" in str(m.content) for m in last)
    assert result.reply == "Rentangnya bisa turun bila rutin bergerak."
    assert [c["name"] for c in result.tool_calls] == ["simulasi_whatif"] * MAX_TOOL_ROUNDS  # jejak tetap lengkap


def test_tanpa_tool_mempertahankan_urutan_dan_teks_model():
    from langchain_core.messages import AIMessage, HumanMessage, SystemMessage, ToolMessage

    from app.graph.kira_graph import _without_tool_turns

    msgs = [SystemMessage("s"), HumanMessage("tanya"),
            AIMessage("cek dulu", tool_calls=[{"name": "hitung_risiko", "args": {}, "id": "a"}]),
            ToolMessage('{"score": 9}', tool_call_id="a", name="hitung_risiko")]
    out = _without_tool_turns(msgs)
    assert [type(m).__name__ for m in out] == ["SystemMessage", "HumanMessage", "AIMessage", "HumanMessage"]
    assert out[2].content == "cek dulu" and not out[2].tool_calls
    assert 'hitung_risiko: {"score": 9}' in out[3].content


async def test_balasan_kosong_dari_model_dicoba_ulang_sekali(session_maker, make_user):
    from tests.graph.fakes import ai

    uid = await make_user()
    chat, _ = install([ai(""), ai("Jalan kakinya sudah kucatat.")], {**SLEEP_ONLY, "sleep": None})
    result = await run(uid, session_maker, input_text="tadi jalan kaki 30 menit")
    assert chat.call_count == 2 and result.reply == "Jalan kakinya sudah kucatat."


@pytest.mark.parametrize("text_,tool", [("hari ini aku makan apa ya?", "rencana_hari_ini"),
                                        ("jadwal olahraga minggu ini gimana", "rencana_minggu"),
                                        ("rencana makan besok apa", "rencana_minggu"),
                                        ("malam ini tidur jam berapa?", "rencana_hari_ini")])
def test_pertanyaan_rencana_menyiapkan_tool_rencana(text_, tool):
    assert plan_calls({"intent": "question_general", "items": [], "drinks": []}, text=text_) == [(tool, {})]
