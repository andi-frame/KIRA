import hashlib
import json
import logging
from dataclasses import dataclass, field
from pathlib import Path

from langchain_core.messages import AIMessage, ToolMessage
from langgraph.errors import GraphRecursionError
from langgraph.graph import END, START, StateGraph
from langgraph.prebuilt import ToolNode, tools_condition

from app.config import settings
from app.core_calc.red_flags import detect_red_flags
from app.db import SessionLocal
from app.graph.nodes.build_context import build_context
from app.graph.nodes.extract import extract
from app.graph.nodes.guards import emergency_reply, fallback_reply, safety_check
from app.graph.nodes.output_guardrail import output_guardrail
from app.graph.nodes.save_logs import save_logs
from app.graph.prompts import FALLBACK_REPLY, LOGGED_BUT_NO_ANSWER_REPLY
from app.graph.state import KiraState
from app.repos import messages as messages_repo
from app.schemas.extraction import Extraction
from app.services.llm import get_chat_model
from app.tools import TOOLS

log = logging.getLogger("kira.graph")

DEMO_CACHE_PATH = Path(__file__).resolve().parents[2] / "seed" / "demo_cache.json"
RECURSION_LIMIT = 12


def cache_key(text: str) -> str:
    return hashlib.sha256(" ".join(text.lower().split()).encode()).hexdigest()[:16]


async def agent(state: KiraState) -> dict:
    model = get_chat_model().bind_tools(TOOLS)
    return {"messages": [await model.ainvoke(state["messages"])]}


def _after_safety(state: KiraState) -> str:
    return "emergency_reply" if state.get("red_flag") else "extract"


def _after_extract(state: KiraState) -> str:
    if state.get("error"):
        return "fallback_reply"
    return "emergency_reply" if state.get("red_flag") else "save_logs"


def build_graph():
    g = StateGraph(KiraState)
    g.add_node("safety_check", safety_check)
    g.add_node("emergency_reply", emergency_reply)
    g.add_node("fallback_reply", fallback_reply)
    g.add_node("extract", extract)
    g.add_node("save_logs", save_logs)
    g.add_node("build_context", build_context)
    g.add_node("agent", agent)
    g.add_node("tools", ToolNode(TOOLS))
    g.add_node("output_guardrail", output_guardrail)

    g.add_edge(START, "safety_check")
    g.add_conditional_edges("safety_check", _after_safety, ["emergency_reply", "extract"])
    g.add_conditional_edges("extract", _after_extract, ["fallback_reply", "emergency_reply", "save_logs"])
    g.add_edge("emergency_reply", END)
    g.add_edge("fallback_reply", END)
    g.add_edge("save_logs", "build_context")
    g.add_edge("build_context", "agent")
    g.add_conditional_edges("agent", tools_condition, {"tools": "tools", END: "output_guardrail"})
    g.add_edge("tools", "agent")
    g.add_edge("output_guardrail", END)
    return g.compile()


kira_graph = build_graph()


@dataclass
class RunResult:
    reply: str
    extraction: Extraction | None = None
    red_flag: str | None = None
    tool_calls: list[dict] = field(default_factory=list)
    log_ids: list[str] = field(default_factory=list)


def _tool_calls(messages: list) -> list[dict]:
    calls: dict[str, dict] = {}
    for m in messages:
        if isinstance(m, AIMessage):
            for tc in m.tool_calls:
                calls[tc["id"]] = {"name": tc["name"], "args": tc["args"], "result": None}
        elif isinstance(m, ToolMessage) and m.tool_call_id in calls:
            try:
                calls[m.tool_call_id]["result"] = json.loads(m.content) if isinstance(m.content, str) else m.content
            except json.JSONDecodeError:
                calls[m.tool_call_id]["result"] = m.content
    return list(calls.values())


def _cached_entry(text: str) -> dict | None:
    """Entri demo cache: string (balasan saja) atau {"reply", "extraction"?}. Tanda bahaya tidak pernah dilewati."""
    if not settings.demo_cache or not DEMO_CACHE_PATH.exists():
        return None
    if detect_red_flags(text=text) is not None:
        return None
    entry = json.loads(DEMO_CACHE_PATH.read_text(encoding="utf-8")).get(cache_key(text))
    return {"reply": entry} if isinstance(entry, str) else entry


async def _persist(session_factory, user_id: str, channel: str, user_text: str, result: RunResult) -> None:
    import uuid

    uid = uuid.UUID(user_id)
    async with session_factory() as session:
        await messages_repo.save(session, uid, "user", user_text, channel, commit=False)
        await messages_repo.save(session, uid, "assistant", result.reply, channel,
                                 tool_calls=result.tool_calls or None, commit=False)
        await session.commit()


async def run_kira_graph(
    user_id: str,
    channel: str,
    *,
    input_text: str | None = None,
    image: bytes | None = None,
    image_kind: str | None = None,
    source: str | None = None,
    session_factory=None,
) -> RunResult:
    text = (input_text or "").strip() or None
    if not text and not image:
        raise ValueError("pesan kosong")
    session_factory = session_factory or SessionLocal
    user_text = text or f"[foto {image_kind or 'makanan'}]"

    config = {
        "recursion_limit": RECURSION_LIMIT,
        "configurable": {"user_id": user_id, "session_factory": session_factory},
    }
    if text and not image and (cached := _cached_entry(text)):
        extraction = Extraction.model_validate(cached["extraction"]) if cached.get("extraction") else None
        log_ids: list[str] = []
        if extraction:
            saved = await save_logs(
                {"extraction": extraction.model_dump(), "source": source or "text", "input_text": text}, config
            )
            log_ids = saved["log_ids"]
        result = RunResult(reply=cached["reply"], extraction=extraction, log_ids=log_ids)
        await _persist(session_factory, user_id, channel, user_text, result)
        return result

    initial: KiraState = {
        "user_id": user_id, "channel": channel, "input_text": text, "image": image, "image_kind": image_kind,
        "source": source or (f"photo_{image_kind}" if image else "text"),
        "notes": [], "log_ids": [], "messages": [],
    }
    # Pantau state per langkah: bila agent gagal setelah catatan tersimpan, hasil parsial tidak boleh hilang
    # (kalau tidak, pengguna disuruh kirim ulang dan makanannya tercatat dua kali).
    out: dict = dict(initial)
    failed = False
    try:
        async for snapshot in kira_graph.astream(initial, config=config, stream_mode="values"):
            out = snapshot
    except GraphRecursionError:
        log.warning("recursion limit reached for user %s", user_id)
        failed = True
    except Exception:  # noqa: BLE001 - kegagalan model/jaringan tidak boleh menjatuhkan chat
        log.exception("graph failed for user %s", user_id)
        failed = True
    if failed:
        out = {**out, "reply": LOGGED_BUT_NO_ANSWER_REPLY if out.get("log_ids") else FALLBACK_REPLY}

    result = RunResult(
        reply=out.get("reply") or FALLBACK_REPLY,
        extraction=Extraction.model_validate(out["extraction"]) if out.get("extraction") else None,
        red_flag=out.get("red_flag"),
        tool_calls=_tool_calls(out.get("messages", [])),
        log_ids=out.get("log_ids", []),
    )
    await _persist(session_factory, user_id, channel, user_text, result)
    return result
