import re

from app.graph.state import KiraState

SAFE_REPLACEMENT = (
    "Maaf, aku tidak bisa membahas obat, dosis, atau diagnosis. Untuk itu tanyakan langsung ke dokter "
    "atau tenaga kesehatan ya. Aku bisa bantu soal pola makan, tidur, dan aktivitasmu."
)

_DRUGS = r"metformin|insulin|glibenklamid|glimepirid|gliklazid|amlodipin|captopril|kaptopril|lisinopril|valsartan|candesartan|bisoprolol|furosemid|hct|simvastatin|atorvastatin"
_PATTERNS = [
    rf"\b({_DRUGS})\b",
    r"\b(dosis|tablet|pil|kapsul)\b.{0,25}\b\d+(\.\d+)?\s?(mg|mcg|ml|unit|iu)\b",
    r"\b(hentikan|stop|berhenti)\b.{0,15}\bobat",
    r"\b(tambah|kurangi|naikkan|turunkan)\b.{0,15}\bdosis",
    r"\bkamu (menderita|terkena|mengidap|pasti (diabetes|hipertensi))\b",
    r"\bkamu (sudah )?(didiagnosis|positif (diabetes|hipertensi))\b",
    r"\bkamu (itu )?aman\b",
    r"\b(dijamin|pasti) aman\b",
    r"\baman (untuk )?(dimakan|dikonsumsi|diminum)\b",
]
_COMPILED = [re.compile(p, re.IGNORECASE) for p in _PATTERNS]


def check_reply(text: str) -> tuple[bool, str]:
    """(ok, teks_final). Balasan yang menyentuh obat/dosis/diagnosis/klaim 'aman' diganti balasan aman."""
    if any(p.search(text) for p in _COMPILED):
        return False, SAFE_REPLACEMENT
    return True, text


def text_of(content) -> str:
    if isinstance(content, str):
        return content
    return "".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")


async def output_guardrail(state: KiraState) -> dict:
    last = state["messages"][-1]
    _, final = check_reply(text_of(last.content).strip())
    return {"reply": final}
