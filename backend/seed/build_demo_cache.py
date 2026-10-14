"""Membuat seed/demo_cache.json dari kalimat skrip demo.

Cache ini HANYA untuk demo/pitching (DEMO_CACHE=true) agar tetap jalan bila LLM lambat atau gagal.
Kalimat tanda bahaya tidak pernah dilayani dari cache. Jalankan ulang bila skrip demo berubah:
    python -m seed.build_demo_cache
"""
import json
from pathlib import Path

from app.graph.kira_graph import cache_key

DEMO_ENTRIES: dict[str, dict] = {
    "Tadi siang nasi padang rendang, es teh manis, terus begadang sampai jam 2.": {
        "reply": (
            "Sip, sudah kucatat: nasi padang pakai rendang, es teh manis, dan kamu tidur larut. "
            "Malam ini coba tidur lebih awal, dan besok es tehnya ganti jadi tawar ya."
        ),
        "extraction": {
            "items": [
                {"name": "nasi putih", "portion_text": "1 porsi", "portion_g_guess": 200, "meal_time": "lunch"},
                {"name": "rendang", "portion_text": "1 potong", "portion_g_guess": 70, "meal_time": "lunch"},
            ],
            "drinks": [{"name": "es teh manis", "size": "gelas", "count": 1}],
            "sleep": {"bed_time": "02:00", "wake_time": None},
            "activity": [],
            "clinical_result": None,
            "intent": "log",
            "summary": "Makan siang nasi padang rendang, es teh manis, tidur jam 2 pagi.",
        },
    },
    "Nanti malam mau makan rendang lagi, boleh berapa?": {
        "reply": (
            "Satu potong rendang (sekitar 70 g) masih sesuai targetmu hari ini kalau nasinya setengah porsi "
            "dan ditambah sayur. Setelah makan, jalan santai 20 menit ya."
        ),
    },
}


def build() -> dict:
    return {cache_key(text): entry for text, entry in DEMO_ENTRIES.items()}


if __name__ == "__main__":
    path = Path(__file__).resolve().parent / "demo_cache.json"
    path.write_text(json.dumps(build(), ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"ditulis: {path} ({len(DEMO_ENTRIES)} entri)")
