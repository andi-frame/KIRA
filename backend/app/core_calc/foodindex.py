"""Indeks n-gram karakter untuk mencocokkan nama makanan yang ditulis bebas ("ayam geperk", "nasi uduk komplit").

Fungsi murni dan deterministik, tanpa dependensi baru. Dipakai sebagai CADANGAN setelah pencocokan nama/alias, dan untuk
saran "maksudmu ...?". Embedding saraf sengaja tidak dipakai: pada uji 26 makanan, "ayam geprek" paling mirip "bubur ayam"
dan "nasi uduk" paling mirip "sambal" (lihat docs/spesifikasi-beranda-perencana.md bagian 2). Untuk tabel gizi, salah cocok
lebih buruk daripada tidak cocok, jadi pemanggil sebaiknya memakai `best_match` yang abstain bila ragu.
"""
import math
import re
import zlib
from collections import Counter
from dataclasses import dataclass

DIM = 2048
N = 3


@dataclass(frozen=True)
class IndexEntry:
    key: str  # id makanan/hidangan
    label: str  # nama atau alias
    kind: str = "food"  # food | dish


@dataclass(frozen=True)
class Hit:
    key: str
    label: str
    kind: str
    score: float


@dataclass(frozen=True)
class FoodIndex:
    entries: tuple[IndexEntry, ...]
    vectors: tuple[dict[int, float], ...]
    idf: dict[int, float]


def normalize(text: str) -> str:
    return " ".join(re.sub(r"[^0-9a-z]+", " ", text.lower()).split())


def _grams(text: str) -> Counter:
    padded = f" {normalize(text)} "
    # crc32, bukan hash(): hash() Python diacak per proses, indeks harus sama di setiap jalan
    return Counter(zlib.crc32(padded[i:i + N].encode()) % DIM for i in range(max(len(padded) - N + 1, 0)))


def _unit(counts: Counter, idf: dict[int, float]) -> dict[int, float]:
    vec = {g: c * idf.get(g, 1.0) for g, c in counts.items()}
    norm = math.sqrt(sum(v * v for v in vec.values()))
    return {g: v / norm for g, v in vec.items()} if norm else {}


def build_index(entries: list[IndexEntry]) -> FoodIndex:
    grams = [_grams(e.label) for e in entries]
    df: Counter = Counter()
    for g in grams:
        df.update(set(g))
    n = max(len(entries), 1)
    idf = {g: math.log((1 + n) / (1 + d)) + 1 for g, d in df.items()}
    return FoodIndex(tuple(entries), tuple(_unit(g, idf) for g in grams), idf)


def search(query: str, index: FoodIndex, top_k: int = 5, min_score: float = 0.0) -> list[Hit]:
    """Entri paling mirip (cosinus TF-IDF n-gram), satu hasil terbaik per key, terurut skor lalu key (stabil)."""
    q = _unit(_grams(query), index.idf)
    if not q:
        return []
    best: dict[str, Hit] = {}
    for entry, vec in zip(index.entries, index.vectors):
        score = sum(w * vec.get(g, 0.0) for g, w in q.items())
        if score >= min_score and (entry.key not in best or score > best[entry.key].score):
            best[entry.key] = Hit(entry.key, entry.label, entry.kind, round(score, 4))
    return sorted(best.values(), key=lambda h: (-h.score, h.key))[:top_k]


def best_match(query: str, index: FoodIndex, min_score: float = 0.7, margin: float = 0.1) -> Hit | None:
    """Satu kecocokan yang meyakinkan, atau None: skor harus tinggi DAN jelas di atas kandidat kedua.
    Ambang bawaan dari data seed: salah ketik ("timunn", "kerupk") ~0,73 dengan selisih >0,15, sedangkan nama hidangan
    yang tidak ada di tabel ("ayam geprek" terhadap makanan tunggal) <0,5."""
    hits = search(query, index, top_k=2)
    if not hits or hits[0].score < min_score:
        return None
    if len(hits) > 1 and hits[0].score - hits[1].score < margin:
        return None
    return hits[0]
