import re

from langchain_core.messages import HumanMessage

from app.graph.state import KiraState

SAFE_REPLACEMENT = (
    "Maaf, aku tidak bisa membahas obat, dosis, diagnosis, atau menyatakan sesuatu itu 'aman'. "
    "Untuk itu tanyakan langsung ke dokter atau tenaga kesehatan ya. "
    "Aku bisa bantu soal pola makan, tidur, dan aktivitasmu, termasuk apa yang masih sesuai targetmu hari ini."
)

# Batang nama obat tanpa batas kata di ujung: "glimepiride", "amlodipine", dst. ikut tertangkap.
_DRUGS = (
    r"metformin|insulin|glibenklamid|glibenclamid|glimepirid|gliklazid|gliclazid|acarbose|sitagliptin|"
    r"empagliflozin|dapagliflozin|amlodipin|captopril|kaptopril|lisinopril|valsartan|candesartan|losartan|"
    r"bisoprolol|furosemid|simvastatin|atorvastatin"
)
_DISEASE = r"(diabetes|hipertensi|darah tinggi|kencing manis)"
_DRUG_WORD = r"(obat|tablet|pil|kapsul|dosis|suntik|injeksi|resep)"
_DOSE = r"\d+(?:[.,]\d+)?\s?(?:mg|mcg|ug|iu|unit)\b"
_PATTERNS = [
    rf"\b(?:{_DRUGS})\w*",
    rf"\b{_DRUG_WORD}\b.{{0,40}}{_DOSE}",
    rf"{_DOSE}.{{0,40}}\b{_DRUG_WORD}\b",
    r"\b(hentikan|stop|berhenti)\b.{0,15}\bobat",
    r"\b(tambah|kurangi|naikkan|turunkan)\b.{0,15}\bdosis",
    rf"\bkamu\b.{{0,25}}\b(menderita|terkena|mengidap|kena|punya\s+(?!riwayat|keluarga)){{1}}.{{0,20}}\b{_DISEASE}",
    rf"\bkamu\s+pasti\s+{_DISEASE}",
    rf"\b(tergolong|termasuk|positif)\b.{{0,12}}\b{_DISEASE}",
    r"\bkamu (sudah )?didiagnosis\b",
    # "aman" apa pun dilarang oleh prompt; kecuali dinegasikan ("belum tentu aman", "tidak aman").
    r"(?<!tidak )(?<!belum tentu )(?<!kurang )(?<!bukan )(?<!belum )\baman\b",
]
_COMPILED = [re.compile(p, re.IGNORECASE) for p in _PATTERNS]


def check_reply(text: str) -> tuple[bool, str]:
    """(ok, teks_final). Balasan yang menyentuh obat/dosis/diagnosis/klaim 'aman' diganti balasan aman."""
    if any(p.search(text) for p in _COMPILED):
        return False, SAFE_REPLACEMENT
    return True, text


_BOLD = re.compile(r"(\*\*|__)(.+?)\1", re.S)
_ITALIC = re.compile(r"(?<![\*\w])\*(?!\s)([^*\n]+?)(?<!\s)\*(?![\*\w])")
_HEADING = re.compile(r"^\s{0,3}#{1,6}\s*", re.M)
_BULLET = re.compile(r"^(\s*)[\*\+]\s+", re.M)
_CODE = re.compile(r"`([^`\n]*)`")


def strip_markdown(text: str) -> str:
    """KIRA menulis seperti pesan chat. Sebagian model tetap memakai markdown (**tebal**, # judul), yang tampil sebagai
    tanda bintang mentah di aplikasi dan WhatsApp, jadi dibersihkan di sini alih-alih bergantung pada kepatuhan model."""
    text = _BOLD.sub(r"\2", text)
    text = _ITALIC.sub(r"\1", text)
    text = _HEADING.sub("", text)
    text = _BULLET.sub(r"\1- ", text)
    text = _CODE.sub(r"\1", text)
    return re.sub(r"\n{3,}", "\n\n", text).strip()


def text_of(content) -> str:
    if isinstance(content, str):
        return content
    return "".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")


# Model selain Claude kadang tergelincir (mis. menyebut "aman"). Beri satu kesempatan menulis ulang sebelum
# balasan diganti kalimat baku, supaya pengguna tetap mendapat jawaban yang berguna.
MAX_REWRITES = 1
REWRITE_INSTRUCTION = (
    "[Instruksi sistem] Balasanmu barusan melanggar aturan KIRA (menyebut obat, dosis, diagnosis, atau kata 'aman'). "
    "Tulis ulang balasan untuk pesan pengguna yang terakhir tanpa hal itu; pakai 'masih sesuai targetmu hari ini' bila perlu. "
    "Jangan menyebut bahwa kamu menulis ulang."
)


async def output_guardrail(state: KiraState) -> dict:
    last = state["messages"][-1]
    text = strip_markdown(text_of(last.content).strip())
    ok, final = check_reply(text)
    if ok:
        return {"reply": text}
    if state.get("guard_retries", 0) < MAX_REWRITES:
        # reply=None memberi tahu graf untuk kembali ke agent sekali lagi.
        return {"reply": None, "guard_retries": state.get("guard_retries", 0) + 1,
                "messages": [HumanMessage(REWRITE_INSTRUCTION)]}
    return {"reply": final}


def after_guardrail(state: KiraState) -> str:
    return "agent" if state.get("reply") is None else "__end__"
