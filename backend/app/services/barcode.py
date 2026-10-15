"""Gizi produk kemasan dari kode batang lewat Open Food Facts (basis data terbuka, lisensi ODbL; wajib mencantumkan sumbernya).

Angka gizi di sana disumbangkan pengguna dan tidak selalu lengkap, jadi: hasil yang tidak lengkap ditandai, tidak ditebak;
nilai yang mustahil ditolak oleh `core_calc.label` seperti pada foto label; dan pengguna selalu bisa kembali ke foto label.
Open Food Facts membatasi 15 permintaan per menit per IP untuk pembacaan produk, jadi hasil di-cache di basis data dan
panggilan keluar dibatasi di sini.
"""
import time
from collections import deque
from dataclasses import dataclass, field
from datetime import timedelta
from typing import Protocol

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Product
from app.timeutil import utcnow

OFF_URL = "https://world.openfoodfacts.org/api/v2/product/{code}.json"
OFF_FIELDS = "code,product_name,brands,quantity,serving_quantity,serving_size,categories_tags,nutriments"
USER_AGENT = "KIRA/1.0 (https://github.com/andi-frame/KIRA)"
SOURCE_NOTE = "Open Food Facts (ODbL)"
FOUND_TTL = timedelta(days=30)
MISSING_TTL = timedelta(days=1)
MAX_CALLS_PER_MINUTE = 10  # di bawah batas 15/menit milik Open Food Facts, menyisakan ruang


class ProductLookupError(Exception):
    """Basis data luar tidak bisa dihubungi atau sedang dibatasi."""


@dataclass
class ProductData:
    barcode: str
    name: str
    brand: str | None = None
    serving_g: float | None = None
    is_drink: bool = False
    per100g: dict[str, float | None] = field(default_factory=dict)  # sugar_g, sodium_mg, fat_g, kcal

    @property
    def complete(self) -> bool:
        """Cukup untuk dicatat: gula dan kalori wajib ada (inti pelacakan KIRA); natrium dan lemak boleh kosong."""
        return self.per100g.get("sugar_g") is not None and self.per100g.get("kcal") is not None


def valid_gtin(code: str) -> bool:
    """Angka cek GS1 (EAN-8, UPC-A, EAN-13, GTIN-14). Menolak salah ketik sebelum memanggil basis data luar."""
    if not code.isdigit() or len(code) not in (8, 12, 13, 14):
        return False
    digits = [int(c) for c in code]
    body, check = digits[:-1], digits[-1]
    total = sum(d * (3 if i % 2 == 0 else 1) for i, d in enumerate(reversed(body)))
    return (10 - total % 10) % 10 == check


def _num(value) -> float | None:
    try:
        n = float(value)
    except (TypeError, ValueError):
        return None
    return n if n >= 0 else None


def parse_off(code: str, payload: dict) -> ProductData | None:
    """Mengubah jawaban Open Food Facts. None bila produk tidak ada atau tanpa nama."""
    if payload.get("status") != 1:
        return None
    p = payload.get("product") or {}
    name = (p.get("product_name") or "").strip()
    if not name:
        return None
    n = p.get("nutriments") or {}
    sodium_g = _num(n.get("sodium_100g"))
    salt_g = _num(n.get("salt_100g"))
    if sodium_g is None and salt_g is not None:
        sodium_g = salt_g / 2.5  # natrium = garam / 2,5
    quantity = str(p.get("quantity") or "").lower()
    categories = p.get("categories_tags") or []
    is_drink = any(u in quantity.replace(" ", "") for u in ("ml", "cl")) or "en:beverages" in categories
    serving = _num(p.get("serving_quantity"))
    return ProductData(
        barcode=code,
        name=name,
        brand=(p.get("brands") or "").split(",")[0].strip() or None,
        serving_g=serving if serving and serving > 0 else None,
        is_drink=is_drink,
        per100g={
            "sugar_g": _num(n.get("sugars_100g")),
            "sodium_mg": None if sodium_g is None else sodium_g * 1000,
            "fat_g": _num(n.get("fat_100g")),
            "kcal": _num(n.get("energy-kcal_100g")),
        },
    )


class OffClient(Protocol):
    async def fetch(self, code: str) -> dict: ...


class HttpOffClient:
    def __init__(self) -> None:
        self._calls: deque[float] = deque()

    def _throttle(self) -> None:
        now = time.monotonic()
        while self._calls and now - self._calls[0] > 60:
            self._calls.popleft()
        if len(self._calls) >= MAX_CALLS_PER_MINUTE:
            raise ProductLookupError("Basis data produk sedang ramai. Coba lagi sebentar lagi, atau foto label kemasannya.")
        self._calls.append(now)

    async def fetch(self, code: str) -> dict:
        self._throttle()
        try:
            async with httpx.AsyncClient(timeout=8, headers={"User-Agent": USER_AGENT}) as client:
                res = await client.get(OFF_URL.format(code=code), params={"fields": OFF_FIELDS})
        except httpx.HTTPError as exc:
            raise ProductLookupError("Basis data produk belum bisa dihubungi. Coba foto label kemasannya.") from exc
        if res.status_code >= 500 or res.status_code == 429:
            raise ProductLookupError("Basis data produk sedang bermasalah. Coba foto label kemasannya.")
        try:
            return res.json()
        except ValueError as exc:
            raise ProductLookupError("Jawaban basis data produk tidak terbaca. Coba foto label kemasannya.") from exc


_client: OffClient = HttpOffClient()


def set_client_for_tests(client: OffClient | None) -> None:
    global _client
    _client = client or HttpOffClient()


def _from_row(row: Product) -> ProductData | None:
    if not row.found:
        return None
    return ProductData(
        barcode=row.barcode, name=row.name or "", brand=row.brand, serving_g=row.serving_g,
        is_drink=row.is_drink, per100g=row.per100g or {},
    )


async def lookup(session: AsyncSession, code: str) -> ProductData | None:
    """Cache dulu (30 hari bila ada, 1 hari bila tidak ada), baru Open Food Facts."""
    row = await session.get(Product, code)
    if row is not None:
        ttl = FOUND_TTL if row.found else MISSING_TTL
        if utcnow() - row.fetched_at < ttl:
            return _from_row(row)
    product = parse_off(code, await _client.fetch(code))
    if row is None:
        row = Product(barcode=code)
        session.add(row)
    row.found, row.fetched_at = product is not None, utcnow()
    row.name = product.name if product else None
    row.brand = product.brand if product else None
    row.serving_g = product.serving_g if product else None
    row.is_drink = product.is_drink if product else False
    row.per100g = product.per100g if product else {}
    await session.commit()
    return product
