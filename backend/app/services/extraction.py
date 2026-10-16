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
    "berapa), question_general (pertanyaan lain), result_input (melaporkan hasil pemeriksaan). "
    "Tidur yang hanya disebut lamanya (\"tidur cuma 5 jam\") diisi sleep.hours. "
    "meal_time HANYA diisi bila pengguna menyebut waktunya (sarapan/makan pagi=breakfast, makan siang/tadi siang=lunch, "
    "makan malam=dinner, camilan/ngemil/selingan=snack); bila tidak disebut, kosongkan (jangan menebak dari jam). "
    "KOREKSI: bila pengguna membetulkan atau membatalkan catatan SEBELUMNYA (\"ralat\", \"maksudku\", \"bukan X tapi Y\", "
    "\"salah catat\", \"tadi cuma setengah porsi\", \"itu makan siang, bukan selingan\", \"hapus yang tadi\"), isi "
    "intent=correction dan correction (action update/delete, target meal/drink/sleep/activity, match_text nama yang "
    "dimaksud, perubahan yang disebut); JANGAN mengisi items/drinks/sleep/activity sebagai catatan baru. Jawaban singkat "
    "atas pertanyaan waktu makan (\"makan siang\", \"selingan\") juga koreksi: correction.meal_time dengan target meal. "
    "REKAM MEDIS: bila pengguna menceritakan riwayat medis (diagnosis dokter, hasil lab lama, obat yang sedang dipakai, "
    "alergi, operasi, vaksin, kunjungan dokter), isi intent=medical_record dan medical_record (kind, title singkat, "
    "recorded_on bila ada tanggal, provider, details, values hasil lab disalin apa adanya); jangan menilai isinya. "
    "Tensi boleh disertai nadi (value.pulse). Detak jantung istirahat tanpa tensi: clinical_result kind=resting_heart_rate, "
    "value {\"bpm\": angka}, intent=result_input."
)
_CATALOG_RULES = (
    "\n\nPetakan makanan ke katalog di bawah: isi dish_id bila itu hidangan di KATALOG HIDANGAN, atau food_id bila "
    "makanan tunggal di KATALOG MAKANAN. Isi id HANYA dari katalog, jangan mengarang id. Hidangan campuran yang tidak ada "
    "di katalog dipecah ke components (maksimal 8): nama bahan sederhana, food_id dari katalog bila ada, dan perkiraan "
    "gram. Minuman hanya masuk drinks, jangan diulang di items. JANGAN mengisi angka gizi apa pun.\n\n"
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


def _system(kind: str, catalog: str | None) -> SystemMessage:
    # Katalog hanya untuk makanan; label/hasil cek tidak memetakan makanan.
    with_catalog = catalog and kind in {"text", "food", "receipt"}
    return SystemMessage(_BASE + _BY_KIND[kind] + (_CATALOG_RULES + catalog if with_catalog else ""))


async def extract_from_text(text: str, catalog: str | None = None) -> Extraction:
    if not text or not text.strip():
        raise ValueError("teks kosong")
    return await _run([_system("text", catalog), HumanMessage(text.strip())])


async def extract_from_image(image: bytes, kind: Literal["food", "receipt", "label", "result"],
                             catalog: str | None = None) -> Extraction:
    if not image:
        raise ValueError("gambar kosong")
    data_uri = f"data:{_mime(image)};base64,{base64.b64encode(image).decode()}"
    content = [
        {"type": "text", "text": "Ekstrak data dari gambar ini."},
        {"type": "image_url", "image_url": {"url": data_uri}},
    ]
    return await _run([_system(kind, catalog), HumanMessage(content=content)])
