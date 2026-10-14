"""Node berbasis aturan: pemeriksaan tanda bahaya dan balasan darurat/cadangan. Tanpa LLM."""
from app.core_calc.red_flags import detect_red_flags
from app.graph.prompts import FALLBACK_REPLY
from app.graph.state import KiraState


async def safety_check(state: KiraState) -> dict:
    flag = detect_red_flags(text=state.get("input_text"))
    if flag is None:
        return {"red_flag": None}
    return {"red_flag": flag.kind, "reply": flag.message}


async def emergency_reply(state: KiraState) -> dict:
    return {"reply": state["reply"]}


async def fallback_reply(state: KiraState) -> dict:
    return {"reply": FALLBACK_REPLY}
