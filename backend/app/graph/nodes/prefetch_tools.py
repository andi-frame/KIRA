"""Menjalankan tool yang hampir pasti dibutuhkan agent SEBELUM agent dipanggil, secara paralel.

Tanpa ini, agent memanggil model untuk meminta tool, menunggu hasilnya, lalu memanggil model lagi untuk menjawab: dua
panggilan model berurutan (masing-masing bisa 10 detik pada model penalaran). Di sini rencana pemanggilan ditentukan oleh aturan
dari hasil ekstraksi, tool dijalankan bersamaan, dan hasilnya dimasukkan ke percakapan sebagai pasangan AIMessage(tool_calls) +
ToolMessage yang sama persis dengan yang akan dibuat agent. Agent langsung menjawab dalam satu panggilan.

Kualitas tidak berubah: tool yang sama, argumen yang sama, angka tetap dari kode (bukan dari model), jejak "Lihat cara KIRA
menghitung" tetap tampil karena pasangan pesan itu masuk ke riwayat, dan agent tetap boleh memanggil tool lain bila perlu.
"""
import asyncio
import json
import logging

from langchain_core.messages import AIMessage, ToolMessage
from langchain_core.runnables import RunnableConfig

from app.graph.state import KiraState
from app.tools import TOOLS

log = logging.getLogger("kira.graph")

MAX_FOODS = 4  # batas pencarian gizi per pesan; sisanya tetap bisa dicari agent bila diperlukan
_BY_NAME = {t.name: t for t in TOOLS}


def plan_calls(extraction: dict | None, notes: list[str] | None = None) -> list[tuple[str, dict]]:
    """Daftar (nama_tool, argumen) yang pasti berguna untuk pesan ini. Fungsi murni, mudah dites."""
    if not extraction:
        return []
    intent = extraction.get("intent")
    items = extraction.get("items") or []
    drinks = extraction.get("drinks") or []
    calls: list[tuple[str, dict]] = []

    if intent in {"log", "question_portion"}:
        seen: set[str] = set()
        for entry in [*items, *drinks]:
            name = (entry.get("name") or "").strip()
            key = name.lower()
            if not name or key in seen or len(seen) >= MAX_FOODS:
                continue
            seen.add(key)
            args: dict = {"makanan": name}
            grams = entry.get("portion_g_guess") if intent == "log" else None
            if grams:
                args["porsi_gram"] = grams
            calls.append(("cari_gizi", args))
        if seen or intent == "question_portion":
            calls.append(("sisa_target_harian", {}))

    elif intent == "result_input" and extraction.get("clinical_result"):
        calls.append(("hitung_risiko", {}))
    return calls


async def _run(name: str, args: dict, config: RunnableConfig):
    return await _BY_NAME[name].ainvoke(args, config=config)


async def prefetch_tools(state: KiraState, config: RunnableConfig) -> dict:
    calls = plan_calls(state.get("extraction"), state.get("notes"))
    if not calls:
        return {}
    results = await asyncio.gather(*[_run(n, a, config) for n, a in calls], return_exceptions=True)
    tool_calls, tool_messages = [], []
    for i, ((name, args), result) in enumerate(zip(calls, results)):
        if isinstance(result, Exception):  # satu tool gagal tidak boleh menjatuhkan jawaban; agent bisa mencoba sendiri
            log.warning("prefetch %s gagal: %s", name, result)
            continue
        call_id = f"prefetch_{i}"
        tool_calls.append({"name": name, "args": args, "id": call_id, "type": "tool_call"})
        tool_messages.append(
            ToolMessage(content=json.dumps(result, ensure_ascii=False, default=str), tool_call_id=call_id, name=name)
        )
    if not tool_calls:
        return {}
    return {"messages": [AIMessage(content="", tool_calls=tool_calls), *tool_messages]}
