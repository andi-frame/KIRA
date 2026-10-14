import re
from dataclasses import dataclass

from app.core_calc.constants import RED_FLAG_BP, RED_FLAG_GLUCOSE, RED_FLAG_KEYWORDS

_URGENT = (
    "Ini bisa jadi tanda bahaya. Segera ke IGD atau Puskesmas terdekat, "
    "atau minta seseorang menemanimu sekarang. KIRA tidak bisa menilai kondisi ini dari chat."
)

# TODO-VERIFY: kosakata gejala (aturan, bukan LLM). Pencocokan berdasarkan kemunculan bersama kata,
# bukan frasa tetap, karena orang menulis "sakit dada", "dadaku nyeri", "nyeri di dada kiri", dst.
_PAIN = {"nyeri", "sakit", "sesak", "nyut", "perih", "ditekan", "menekan", "tertindih", "berat", "panas"}
_BREATH_WORDS = {"napas", "nafas"}
_BREATH_TROUBLE = {"sesak", "susah", "sulit", "berat", "tersengal", "engap"}
_NOT_CHEST = {"ayam", "bebek", "sapi", "kalkun", "goreng", "bakar", "panggang"}
_STROKE_SINGLE = {"mencong", "perot", "pelo", "lumpuh", "cadel"}
_NUMB_CONTEXT = {"kiri", "kanan", "sebelah", "separuh", "setengah", "wajah", "tangan", "kaki", "mulut"}
_FAINT = {"pingsan", "kejang"}
_WINDOW = 3  # jarak maksimum (dalam kata) antara kata tubuh dan kata gejala

_TOKEN = re.compile(r"[a-z0-9]+")
_BP_CONTEXT = re.compile(r"\b(tensi|tekanan|td)\b|tekanan darah")
_BP_VALUE = re.compile(r"\b(\d{2,3})\s*/\s*(\d{2,3})\b")
_GLUCOSE_CONTEXT = re.compile(
    r"\b(?:gula darah|gula puasa|gula sewaktu|gds|gdp|glukosa|gulaku)\b\D{0,15}?(\d{2,3})\b(?!\s*(?:gram|gr|g|sdm|sdt|sendok))"
)
_PLAUSIBLE_GLUCOSE = (20, 800)


def _tokens(text: str) -> list[str]:
    return _TOKEN.findall(text.lower())


def _near(tokens: list[str], index: int, vocab: set[str]) -> bool:
    lo, hi = max(0, index - _WINDOW), index + _WINDOW + 1
    return any(t in vocab for i, t in enumerate(tokens[lo:hi], start=lo) if i != index)


def _symptom_in(text: str) -> bool:
    lowered = text.lower()
    if any(keyword in lowered for keyword in RED_FLAG_KEYWORDS):
        return True
    tokens = _tokens(text)
    for i, tok in enumerate(tokens):
        nxt = tokens[i + 1] if i + 1 < len(tokens) else ""
        if (tok == "dada" or tok == "dadaku") and nxt not in _NOT_CHEST and _near(tokens, i, _PAIN):
            return True
        if tok in _BREATH_WORDS and _near(tokens, i, _BREATH_TROUBLE):
            return True
        if tok in _STROKE_SINGLE or tok in _FAINT:
            return True
        if tok == "sesak" and nxt not in {"perut"}:
            return True
        if tok == "mati" and nxt == "rasa" and _near(tokens, i, _NUMB_CONTEXT):
            return True
    return False


def _numbers_in(text: str) -> tuple[tuple[int, int] | None, float | None]:
    """Angka tensi/gula yang diketik di teks. Hanya dengan kata konteks; angka mustahil diabaikan."""
    lowered = text.lower()
    bp = None
    if _BP_CONTEXT.search(lowered):
        for match in _BP_VALUE.finditer(lowered):
            sys_, dia = int(match.group(1)), int(match.group(2))
            if 50 <= sys_ <= 300 and 30 <= dia <= 200 and dia < sys_:
                bp = (sys_, dia)
                break
    glucose = None
    match = _GLUCOSE_CONTEXT.search(lowered)
    if match and _PLAUSIBLE_GLUCOSE[0] <= int(match.group(1)) <= _PLAUSIBLE_GLUCOSE[1]:
        glucose = float(match.group(1))
    return bp, glucose


@dataclass(frozen=True)
class RedFlag:
    kind: str  # symptom | blood_pressure | glucose_high | glucose_low
    message: str


def detect_red_flags(
    text: str | None = None,
    glucose_mg_dl: float | None = None,
    bp: tuple[int, int] | None = None,
) -> RedFlag | None:
    if text:
        if _symptom_in(text):
            return RedFlag("symptom", _URGENT)
        typed_bp, typed_glucose = _numbers_in(text)
        bp = bp or typed_bp
        glucose_mg_dl = glucose_mg_dl if glucose_mg_dl is not None else typed_glucose
    if bp is not None and (bp[0] >= RED_FLAG_BP[0] or bp[1] >= RED_FLAG_BP[1]):
        return RedFlag("blood_pressure", f"Tekanan darah {bp[0]}/{bp[1]} sangat tinggi. {_URGENT}")
    if glucose_mg_dl is not None:
        if glucose_mg_dl <= RED_FLAG_GLUCOSE["low"]:
            return RedFlag("glucose_low", f"Gula darah {glucose_mg_dl:g} mg/dL sangat rendah. {_URGENT}")
        if glucose_mg_dl >= RED_FLAG_GLUCOSE["high"]:
            return RedFlag("glucose_high", f"Gula darah {glucose_mg_dl:g} mg/dL sangat tinggi. {_URGENT}")
    return None


_TIME = re.compile(r"^([01]\d|2[0-3]):([0-5]\d)$")


def _minutes(value: str) -> int:
    match = _TIME.match(value)
    if not match:
        raise ValueError(f"format jam harus HH:MM: {value!r}")
    return int(match.group(1)) * 60 + int(match.group(2))


def parse_sleep_hours(bed_time: str, wake_time: str) -> float:
    bed, wake = _minutes(bed_time), _minutes(wake_time)
    minutes = wake - bed if wake > bed else wake + 24 * 60 - bed
    return minutes / 60
