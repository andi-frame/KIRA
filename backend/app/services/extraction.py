import base64
from typing import Literal

from langchain_core.messages import HumanMessage, SystemMessage
from pydantic import ValidationError

from app.schemas.extraction import Extraction
from app.config import settings
from app.services.hedge import hedged
from app.services.llm import get_extract_model


class ExtractionError(Exception):
    """Ekstraksi gagal (model error, timeout, atau keluaran melanggar skema)."""


_BASE = (
    "Kamu mengekstrak data kesehatan harian dari pesan pengguna berbahasa Indonesia (boleh campur slang) "
    "menjadi JSON sesuai skema. Isi hanya yang disebut pengguna; jangan menebak yang tidak ada. "
    "Jangan menghitung kalori, gula, atau risiko. Perkiraan gram porsi (portion_g_guess) boleh diisi kasar. "
    "Jam tidur/bangun format 24 jam HH:MM. intent: log (mencatat), question_portion (bertanya boleh makan "
    "berapa), question_general (pertanyaan lain), result_input (melaporkan hasil pemeriksaan)."
)
_BY_KIND = {
    "text": "",
    "food": " Input adalah FOTO makanan: sebutkan tiap makanan/minuman yang terlihat.",
    "receipt": " Input adalah FOTO struk belanja: tiap item makanan/minuman di struk menjadi item atau drink.",
    "label": (
        " Input adalah FOTO tabel informasi nilai gizi di kemasan: isi label dengan nama produk, apakah minuman, "
        "basis (per_serving bila angka per sajian, per_100g bila per 100 g/ml), takaran saji dalam gram atau ml, "
        "dan gula (g), natrium (mg), lemak total (g), energi (kkal) PERSIS seperti tercetak. Zat yang tidak tertera "
        "dibiarkan kosong, jangan menebak atau menghitung. servings_consumed=1 kecuali pengguna menyebut lain. "
        "intent=log. Jangan mengisi items atau drinks."
    ),
    "result": (
        " Input adalah FOTO hasil pemeriksaan (lab/CKG/tensimeter): isi clinical_result dengan kind dan value "
        "(glukosa {mg_dl}, tensi {sys, dia}, hba1c {percent}, lingkar perut {cm}); intent=result_input."
    ),
}


def _mime(image: bytes) -> str:
    if image.startswith(b"\x89PNG"):
        return "image/png"
    if image[:4] == b"RIFF" and image[8:12] == b"WEBP":
        return "image/webp"
    return "image/jpeg"


async def _run(messages: list) -> Extraction:
    try:
        runnable = get_extract_model().with_structured_output(Extraction)
        raw = await hedged(lambda: runnable.ainvoke(messages), after=settings.llm_hedge_after_seconds)
        return raw if isinstance(raw, Extraction) else Extraction.model_validate(raw)
    except ValidationError as exc:
        raise ExtractionError("keluaran model melanggar skema") from exc
    except Exception as exc:  # noqa: BLE001 - semua kegagalan model/jaringan dibungkus
        raise ExtractionError("model ekstraksi gagal") from exc


async def extract_from_text(text: str) -> Extraction:
    if not text or not text.strip():
        raise ValueError("teks kosong")
    return await _run([SystemMessage(_BASE + _BY_KIND["text"]), HumanMessage(text.strip())])


async def extract_from_image(image: bytes, kind: Literal["food", "receipt", "label", "result"]) -> Extraction:
    if not image:
        raise ValueError("gambar kosong")
    data_uri = f"data:{_mime(image)};base64,{base64.b64encode(image).decode()}"
    content = [
        {"type": "text", "text": "Ekstrak data dari gambar ini."},
        {"type": "image_url", "image_url": {"url": data_uri}},
    ]
    return await _run([SystemMessage(_BASE + _BY_KIND[kind]), HumanMessage(content=content)])
