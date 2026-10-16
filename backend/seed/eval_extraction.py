"""Evaluasi akurasi ekstraksi pada kalimat check-in berbahasa campur.

Memanggil model ekstraksi SUNGGUHAN (butuh ANTHROPIC_API_KEY, berbayar), jadi tidak ikut `pytest`.
Menilai: apakah makanan, minuman, jam tidur, dan intent yang diharapkan terambil. Bukan penilaian gizi.
    uv run python -m seed.eval_extraction
"""
import asyncio
import time
from dataclasses import dataclass, field

from app.schemas.extraction import Extraction
from app.services.extraction import ExtractionError, extract_from_text


@dataclass
class Case:
    text: str
    foods: list[str] = field(default_factory=list)
    drinks: list[str] = field(default_factory=list)
    bed_time: str | None = None
    intent: str = "log"


@dataclass
class Score:
    hits: int
    total: int
    missed: list[str]


CASES: list[Case] = [
    Case("Tadi siang nasi padang rendang, es teh manis, terus begadang sampai jam 2.", ["nasi", "rendang"], ["teh"], "02:00"),
    Case("pagi ini sarapan bubur ayam sama kopi susu gula aren", ["bubur"], ["kopi"]),
    Case("lunch tadi nasi goreng + telor ceplok, minumnya es jeruk", ["nasi goreng", "telur"], ["jeruk"]),
    Case("semalem tidur jam 1 gara-gara ngerjain deadline, bangun jam 6", [], [], "01:00"),
    Case("makan malem soto ayam doang, ga minum manis", ["soto"]),
    Case("tadi ngemil keripik sama boba brown sugar", ["keripik"], ["boba"]),
    Case("sarapan roti tawar selai coklat dua lembar, teh hangat tanpa gula", ["roti"], ["teh"]),
    Case("gue makan mie ayam bakso siang ini, es teh tawar", ["mie ayam"], ["teh"]),
    Case("Dinner: gado-gado, no nasi, minum air putih aja", ["gado-gado"], ["air putih"]),
    Case("jam 11 malem baru tidur, tadi sore makan martabak manis", ["martabak"], [], "23:00"),
    Case("breakfast pake oatmeal sama pisang, kopi hitam", ["oatmeal", "pisang"], ["kopi"]),
    Case("siang makan ayam geprek sambel level 5, es kopi susu", ["ayam geprek"], ["kopi"]),
    Case("abis maghrib makan pecel lele, nasi setengah, es teh manis", ["pecel lele", "nasi"], ["teh"]),
    Case("tadi pagi cuma minum susu coklat sama makan roti bakar", ["roti"], ["susu"]),
    Case("sahur nasi, telur dadar, tempe goreng, air putih", ["nasi", "telur", "tempe"], ["air putih"]),
    Case("tidur jam 12 teng semalem, pagi sarapan lontong sayur", ["lontong"], [], "00:00"),
    Case("makan siang sate ayam 10 tusuk pake lontong, es jeruk nipis", ["sate", "lontong"], ["jeruk"]),
    Case("snack sore: pisang goreng 2 biji, teh manis hangat", ["pisang goreng"], ["teh"]),
    Case("lagi diet jadi makan salad ayam aja, minum green tea", ["salad"], ["green tea"]),
    Case("nasi uduk komplit pagi tadi, kopi tubruk", ["nasi uduk"], ["kopi"]),
    Case("Nanti malam mau makan rendang lagi, boleh berapa?", [], [], None, "question_portion"),
    Case("boleh ga sih makan durian kalau lagi prediabetes?", [], [], None, "question_portion"),
]


def _has(names: list[str], wanted: str) -> bool:
    wanted = wanted.lower()
    return any(wanted in name.lower() for name in names)


def score_case(case: Case, result: Extraction) -> Score:
    checks: list[tuple[str, bool]] = [("intent " + case.intent, result.intent == case.intent)]
    food_names = [i.name for i in result.items]
    drink_names = [d.name for d in result.drinks]
    checks += [(f, _has(food_names, f)) for f in case.foods]
    checks += [(d, _has(drink_names, d)) for d in case.drinks]
    if case.bed_time:
        got = result.sleep.bed_time if result.sleep else None
        checks.append((f"tidur {case.bed_time}", got == case.bed_time))
    return Score(hits=sum(ok for _, ok in checks), total=len(checks), missed=[n for n, ok in checks if not ok])


def summarize(scores: list[Score | None]) -> dict:
    valid = [s for s in scores if s is not None]
    total = sum(s.total for s in valid)
    return {
        "cases": len(scores),
        "failed": len(scores) - len(valid),
        "hit_rate": (sum(s.hits for s in valid) / total) if total else 0.0,
    }


async def main() -> None:
    from app.config import settings

    scores: list[Score | None] = []
    latencies: list[float] = []
    for case in CASES:
        started = time.perf_counter()
        try:
            score = score_case(case, await extract_from_text(case.text))
        except ExtractionError:
            score = None
        latencies.append(time.perf_counter() - started)
        scores.append(score)
        status = "GAGAL" if score is None else f"{score.hits}/{score.total}" + (f" kurang: {', '.join(score.missed)}" if score.missed else "")
        print(f"- {case.text[:60]:<60} {latencies[-1]:5.1f}s {status}")
    summary = summarize(scores)
    ordered = sorted(latencies)
    print(f"\nModel: {settings.llm_model_extract}")
    print(f"Kasus: {summary['cases']} | ekstraksi gagal: {summary['failed']} | butir terambil: {summary['hit_rate']:.0%}")
    print(f"Latensi: rata-rata {sum(latencies) / len(latencies):.1f}s | median {ordered[len(ordered) // 2]:.1f}s | terlama {ordered[-1]:.1f}s")


if __name__ == "__main__":
    asyncio.run(main())
