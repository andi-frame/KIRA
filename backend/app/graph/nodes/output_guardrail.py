import re

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


def text_of(content) -> str:
    if isinstance(content, str):
        return content
    return "".join(b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text")


async def output_guardrail(state: KiraState) -> dict:
    last = state["messages"][-1]
    _, final = check_reply(text_of(last.content).strip())
    return {"reply": final}
