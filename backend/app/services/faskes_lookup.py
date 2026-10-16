"""Fasilitas kesehatan terdekat dari lokasi pengguna, dari data peta sungguhan.

Urutan sumber (yang pertama berhasil dipakai):
1. Google Places (New) bila GOOGLE_PLACES_API_KEY diisi: pencarian teks "puskesmas", "klinik", "rumah sakit" di sekitar titik.
2. OpenStreetMap lewat Overpass API (tanpa kunci; server publik kadang penuh, jadi dicoba bergantian).
3. Tabel `faskes` (data contoh di database) sebagai cadangan terakhir, ditandai source="seed".

Hasil Overpass disimpan sementara di memori (per sel sekitar 1 km, 6 jam) agar tidak membebani server publik. Tiap hasil
membawa tautan Google Maps (rute) yang bisa dibuka tanpa kunci apa pun.
"""
import asyncio
import logging
import re
import time
from urllib.parse import quote

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.repos import faskes as faskes_repo
from app.repos.faskes import haversine_km

log = logging.getLogger("kira.faskes")

USER_AGENT = "KIRA-health-app/1.0 (hackathon prototype; contact: see repository)"
RADIUS_M = 5000
MAX_RESULTS = 8
CACHE_TTL_S = 6 * 3600
OVERPASS_TIMEOUT_S = 12
GOOGLE_TIMEOUT_S = 8

_cache: dict[tuple[float, float], tuple[float, list[dict]]] = {}

_PUSKESMAS = re.compile(r"puskesmas|pusat kesehatan masyarakat|pkm\b", re.IGNORECASE)
_POSYANDU = re.compile(r"posyandu|posbindu", re.IGNORECASE)
_HOSPITAL = re.compile(r"rumah sakit|\brsu?d?\b|\brs[a-z]{0,3}\b|hospital", re.IGNORECASE)


# Tempat yang bukan untuk cek rutin gula darah/tensi (kecantikan, gigi, hewan, dan rumah sakit khusus seperti ginjal, mata, jiwa,
# ibu dan anak): dibuang dari daftar. Pengguna yang membutuhkannya tetap bisa mencari sendiri lewat tombol Google Maps.
_NOT_CHECKUP = re.compile(
    r"aesthetic|estetik|kecantikan|beauty|skin|derma|klinik gigi|dental|dokter gigi|gigi|mulut|rsgm|veteriner|hewan|\bvet\b|\bpet\b|"
    r"salon|\bspa\b|bersalin|ibu dan anak|\brsia\b|laser|ginjal|\bmata\b|\bjiwa\b|kanker|\btht\b",
    re.IGNORECASE,
)
# Puskesmas dan rumah sakit lebih berguna untuk cek rutin dan tindak lanjut: dihitung "lebih dekat" saat mengurutkan.
_KIND_WEIGHT = {"puskesmas": 0.6, "posyandu": 0.7, "rumah_sakit": 0.8, "klinik": 1.0}


def classify(name: str, hint: str | None = None) -> str:
    """posyandu | puskesmas | rumah_sakit | klinik."""
    if _POSYANDU.search(name):
        return "posyandu"
    if _PUSKESMAS.search(name):
        return "puskesmas"
    if hint == "hospital" or _HOSPITAL.search(name):
        return "rumah_sakit"
    return "klinik"


def maps_link(lat: float, lng: float, name: str | None = None) -> str:
    """Tautan Google Maps (tanpa kunci) ke titik itu; dibuka di aplikasi Maps bila terpasang."""
    query = f"{name} @{lat},{lng}" if name else f"{lat},{lng}"
    return f"https://www.google.com/maps/search/?api=1&query={quote(query)}"


def directions_link(lat: float, lng: float) -> str:
    return f"https://www.google.com/maps/dir/?api=1&destination={lat},{lng}&travelmode=driving"


def search_link(lat: float, lng: float, query: str = "puskesmas") -> str:
    """Pencarian di Google Maps di sekitar titik pengguna; bekerja walau semua sumber data gagal."""
    return f"https://www.google.com/maps/search/{quote(query)}/@{lat},{lng},15z"


def _finish(raw: list[dict], lat: float, lng: float, source: str) -> list[dict]:
    seen: set[tuple[str, float, float]] = set()
    out = []
    for r in raw:
        if _NOT_CHECKUP.search(r["name"]):
            continue
        key = (r["name"].lower(), round(r["lat"], 3), round(r["lng"], 3))
        if key in seen:
            continue
        seen.add(key)
        out.append({**r, "source": source, "distance_km": round(haversine_km(lat, lng, r["lat"], r["lng"]), 2),
                    "maps_url": maps_link(r["lat"], r["lng"], r["name"]),
                    "directions_url": directions_link(r["lat"], r["lng"])})
    out.sort(key=lambda f: f["distance_km"] * _KIND_WEIGHT.get(f["kind"], 1.0))
    return out[:MAX_RESULTS]


# ----- OpenStreetMap -----

def _overpass_query(lat: float, lng: float) -> str:
    around = f"(around:{RADIUS_M},{lat},{lng})"
    return (f'[out:json][timeout:20];(nwr["amenity"~"^(hospital|clinic|doctors)$"]{around};'
            f'nwr["healthcare"~"^(centre|clinic|hospital|doctor)$"]{around};);out center 60;')


def parse_overpass(data: dict) -> list[dict]:
    out = []
    for el in data.get("elements", []):
        tags = el.get("tags") or {}
        name = (tags.get("name") or "").strip()
        point = el if "lat" in el else el.get("center") or {}
        if not name or "lat" not in point or "lon" not in point:
            continue
        address = ", ".join(p for p in (tags.get("addr:full") or " ".join(
            x for x in (tags.get("addr:street"), tags.get("addr:housenumber")) if x), tags.get("addr:city")) if p) or None
        out.append({"id": f"osm:{el.get('type', 'n')[0]}{el.get('id')}", "name": name,
                    "kind": classify(name, "hospital" if tags.get("amenity") == "hospital" or tags.get("healthcare") == "hospital" else None),
                    "address": address, "lat": float(point["lat"]), "lng": float(point["lon"]),
                    "phone": tags.get("phone") or tags.get("contact:phone"), "opening_hours": tags.get("opening_hours")})
    return out


async def _overpass(lat: float, lng: float) -> list[dict]:
    cell = (round(lat, 2), round(lng, 2))
    cached = _cache.get(cell)
    if cached and time.monotonic() - cached[0] < CACHE_TTL_S:
        return cached[1]
    urls = [u.strip() for u in settings.overpass_urls.split(",") if u.strip()]
    async with httpx.AsyncClient(timeout=OVERPASS_TIMEOUT_S, headers={"User-Agent": USER_AGENT, "Accept": "application/json"}) as client:
        for url in urls:
            try:
                resp = await client.post(url, data={"data": _overpass_query(lat, lng)})
                resp.raise_for_status()
                found = parse_overpass(resp.json())
            except (httpx.HTTPError, ValueError) as exc:
                log.warning("overpass %s gagal: %s", url, exc)
                continue
            _cache[cell] = (time.monotonic(), found)
            return found
    return []


# ----- Google Places (New) -----

def parse_google(data: dict) -> list[dict]:
    out = []
    for p in data.get("places", []):
        loc = p.get("location") or {}
        name = ((p.get("displayName") or {}).get("text") or "").strip()
        if not name or "latitude" not in loc or "longitude" not in loc:
            continue
        out.append({"id": f"google:{p.get('id')}", "name": name,
                    "kind": classify(name, "hospital" if "hospital" in (p.get("types") or []) else None),
                    "address": p.get("formattedAddress"), "lat": float(loc["latitude"]), "lng": float(loc["longitude"]),
                    "phone": p.get("nationalPhoneNumber"), "opening_hours": None})
    return out


async def _google(lat: float, lng: float) -> list[dict]:
    headers = {"X-Goog-Api-Key": settings.google_places_api_key, "Content-Type": "application/json",
               "X-Goog-FieldMask": "places.id,places.displayName,places.formattedAddress,places.location,places.types,places.nationalPhoneNumber"}

    async def one(client: httpx.AsyncClient, query: str) -> list[dict]:
        body = {"textQuery": query, "languageCode": "id", "maxResultCount": 10,
                "locationBias": {"circle": {"center": {"latitude": lat, "longitude": lng}, "radius": float(RADIUS_M)}}}
        try:
            resp = await client.post("https://places.googleapis.com/v1/places:searchText", json=body, headers=headers)
            resp.raise_for_status()
            return parse_google(resp.json())
        except (httpx.HTTPError, ValueError) as exc:
            log.warning("google places '%s' gagal: %s", query, exc)
            return []

    async with httpx.AsyncClient(timeout=GOOGLE_TIMEOUT_S) as client:
        groups = await asyncio.gather(*[one(client, q) for q in ("puskesmas", "klinik kesehatan", "rumah sakit")])
    return [r for g in groups for r in g]


# ----- gabungan -----

async def nearby(session: AsyncSession, lat: float, lng: float) -> dict:
    """{"faskes": [...], "source": google|osm|seed, "search_url": ...}. Selalu mengembalikan sesuatu."""
    found: list[dict] = []
    source = "seed"
    if settings.google_places_api_key:
        found, source = await _google(lat, lng), "google"
    if not found:
        found, source = await _overpass(lat, lng), "osm"
    results = _finish(found, lat, lng, source) if found else []
    if not results:
        source = "seed"
        results = [{**f, "id": f"seed:{f['id']}", "phone": None, "opening_hours": None, "source": "seed",
                    "maps_url": maps_link(f["lat"], f["lng"], f["name"]), "directions_url": directions_link(f["lat"], f["lng"])}
                   for f in await faskes_repo.nearby(session, lat, lng, limit=MAX_RESULTS)]
    return {"faskes": results, "source": source, "search_url": search_link(lat, lng)}
