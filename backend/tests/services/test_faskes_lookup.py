"""Fasilitas kesehatan terdekat: Google Places -> OpenStreetMap -> data contoh, dengan tautan Google Maps."""
import httpx
import pytest

from app.config import settings
from app.services import faskes_lookup

LAT, LNG = -6.8915, 107.6107

OVERPASS = {"elements": [
    {"type": "node", "id": 1, "lat": -6.8920, "lon": 107.6110,
     "tags": {"name": "Puskesmas Dago", "amenity": "clinic", "addr:street": "Jl. Dago", "addr:housenumber": "12", "phone": "022-111"}},
    {"type": "way", "id": 2, "center": {"lat": -6.9000, "lon": 107.6200},
     "tags": {"name": "RS Santosa", "amenity": "hospital"}},
    {"type": "node", "id": 3, "lat": -6.8930, "lon": 107.6120, "tags": {"amenity": "clinic"}},  # tanpa nama: dibuang
    {"type": "node", "id": 4, "lat": -6.8921, "lon": 107.6111, "tags": {"name": "Puskesmas Dago", "amenity": "clinic"}},  # ganda
    {"type": "node", "id": 5, "lat": -6.8940, "lon": 107.6150, "tags": {"name": "Klinik Sehat", "healthcare": "clinic"}},
]}

GOOGLE = {"places": [
    {"id": "abc", "displayName": {"text": "Puskesmas Cicendo"}, "formattedAddress": "Jl. Cicendo No. 1, Bandung",
     "location": {"latitude": -6.8905, "longitude": 107.6100}, "types": ["health"], "nationalPhoneNumber": "022 222"},
    {"id": "def", "displayName": {"text": "Rumah Sakit Hasan Sadikin"}, "location": {"latitude": -6.8975, "longitude": 107.5950},
     "types": ["hospital", "health"]},
]}


@pytest.mark.parametrize("name,hint,kind", [
    ("Puskesmas Dago", None, "puskesmas"), ("UPTD Pusat Kesehatan Masyarakat Sukajadi", None, "puskesmas"),
    ("Posyandu Melati 3", None, "posyandu"), ("RSUD Kota Bandung", None, "rumah_sakit"),
    ("Rumah Sakit Borromeus", None, "rumah_sakit"), ("Klinik Pratama Sehat", None, "klinik"),
    ("Santosa", "hospital", "rumah_sakit"),
])
def test_jenis_ditebak_dari_nama_dan_petunjuk(name, hint, kind):
    assert faskes_lookup.classify(name, hint) == kind


def test_parse_overpass_membuang_tanpa_nama_dan_mengambil_titik_tengah_area():
    parsed = faskes_lookup.parse_overpass(OVERPASS)
    assert [p["name"] for p in parsed] == ["Puskesmas Dago", "RS Santosa", "Puskesmas Dago", "Klinik Sehat"]
    assert parsed[0]["address"] == "Jl. Dago 12" and parsed[0]["phone"] == "022-111"
    assert (parsed[1]["lat"], parsed[1]["lng"], parsed[1]["kind"]) == (-6.9, 107.62, "rumah_sakit")


def test_tautan_maps_tanpa_kunci_dan_pencarian_di_sekitar_titik():
    assert faskes_lookup.directions_link(-6.89, 107.61) == "https://www.google.com/maps/dir/?api=1&destination=-6.89,107.61&travelmode=driving"
    assert faskes_lookup.maps_link(-6.89, 107.61, "Puskesmas Dago").startswith("https://www.google.com/maps/search/?api=1&query=Puskesmas")
    assert faskes_lookup.search_link(-6.89, 107.61) == "https://www.google.com/maps/search/puskesmas/@-6.89,107.61,15z"


async def test_osm_dipakai_tanpa_kunci_google_terurut_jarak_tanpa_ganda(session_maker, monkeypatch):
    async def fake(lat, lng):
        return faskes_lookup.parse_overpass(OVERPASS)

    monkeypatch.setattr(faskes_lookup, "_overpass", fake)
    async with session_maker() as s:
        out = await faskes_lookup.nearby(s, LAT, LNG)
    assert out["source"] == "osm"
    names = [f["name"] for f in out["faskes"]]
    assert names.count("Puskesmas Dago") == 1 and names[0] == "Puskesmas Dago"
    assert all(f["distance_km"] > 0 for f in out["faskes"])
    assert all(f["directions_url"].startswith("https://www.google.com/maps/dir/") for f in out["faskes"])
    assert out["search_url"].startswith("https://www.google.com/maps/search/puskesmas/")


async def test_google_didahulukan_bila_kunci_ada_dan_gagal_jatuh_ke_osm(session_maker, monkeypatch):
    monkeypatch.setattr(settings, "google_places_api_key", "kunci-uji")
    calls = []

    async def google(lat, lng):
        calls.append("google")
        return faskes_lookup.parse_google(GOOGLE)

    monkeypatch.setattr(faskes_lookup, "_google", google)
    async with session_maker() as s:
        out = await faskes_lookup.nearby(s, LAT, LNG)
    assert calls == ["google"] and out["source"] == "google"
    assert out["faskes"][0]["name"] == "Puskesmas Cicendo" and out["faskes"][1]["kind"] == "rumah_sakit"

    async def google_down(lat, lng):
        return []

    async def osm(lat, lng):
        return faskes_lookup.parse_overpass(OVERPASS)

    monkeypatch.setattr(faskes_lookup, "_google", google_down)
    monkeypatch.setattr(faskes_lookup, "_overpass", osm)
    async with session_maker() as s:
        assert (await faskes_lookup.nearby(s, LAT, LNG))["source"] == "osm"


async def test_semua_sumber_gagal_jatuh_ke_data_contoh_tetap_ada_tautan(session_maker, monkeypatch):
    async def empty(lat, lng):
        return []

    monkeypatch.setattr(faskes_lookup, "_overpass", empty)
    async with session_maker() as s:
        out = await faskes_lookup.nearby(s, LAT, LNG)
    assert out["source"] == "seed" and out["faskes"], "data contoh harus ada"
    assert out["faskes"][0]["id"].startswith("seed:") and out["faskes"][0]["maps_url"]
    assert out["search_url"]


async def test_overpass_mencoba_server_berikutnya_dan_menyimpan_cache(monkeypatch):
    monkeypatch.setattr(settings, "overpass_urls", "https://down.example/api,https://ok.example/api")
    seen: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        seen.append(str(request.url))
        assert "User-Agent" in request.headers and b"around%3A5000" in request.content
        if "down.example" in str(request.url):
            return httpx.Response(502, text="penuh")
        return httpx.Response(200, json=OVERPASS)

    real = httpx.AsyncClient
    monkeypatch.setattr(faskes_lookup.httpx, "AsyncClient",
                        lambda **kw: real(transport=httpx.MockTransport(handler), **kw))
    first = await faskes_lookup._overpass(LAT, LNG)
    assert len(first) == 4 and seen == ["https://down.example/api", "https://ok.example/api"]
    await faskes_lookup._overpass(LAT, LNG)
    assert len(seen) == 2  # kedua dari cache


async def test_klinik_kecantikan_dibuang_dan_puskesmas_diutamakan_atas_klinik_sedikit_lebih_dekat(session_maker, monkeypatch):
    raw = [
        {"id": "a", "name": "Bandung Skin Centre", "kind": "klinik", "address": None, "lat": -6.8916, "lng": 107.6108},
        {"id": "b", "name": "Klinik Sehat", "kind": "klinik", "address": None, "lat": -6.8942, "lng": 107.6107},
        {"id": "c", "name": "Puskesmas Sekeloa", "kind": "puskesmas", "address": None, "lat": -6.8951, "lng": 107.6107},
    ]

    async def fake(lat, lng):
        return raw

    monkeypatch.setattr(faskes_lookup, "_overpass", fake)
    async with session_maker() as s:
        out = await faskes_lookup.nearby(s, LAT, LNG)
    names = [f["name"] for f in out["faskes"]]
    assert "Bandung Skin Centre" not in names
    assert names == ["Puskesmas Sekeloa", "Klinik Sehat"]  # puskesmas sedikit lebih jauh tetap didahulukan
    assert out["faskes"][0]["distance_km"] > out["faskes"][1]["distance_km"]  # jarak yang ditampilkan tetap jujur


async def test_rumah_sakit_khusus_dibuang_tetapi_rumah_sakit_umum_tetap(session_maker, monkeypatch):
    raw = [{"id": str(i), "name": n, "kind": "rumah_sakit", "address": None, "lat": -6.8916 - i * 0.0005, "lng": 107.6108}
           for i, n in enumerate(["RSGM Unpad", "Rumah Sakit Ginjal Nyonya Habibie", "Rumah Sakit Mata Cicendo", "RSIA Kota Bandung",
                                  "Rumah Sakit Advent", "Rumah Sakit Jiwa Provinsi"])]

    async def fake(lat, lng):
        return raw

    monkeypatch.setattr(faskes_lookup, "_overpass", fake)
    async with session_maker() as s:
        out = await faskes_lookup.nearby(s, LAT, LNG)
    assert [f["name"] for f in out["faskes"]] == ["Rumah Sakit Advent"]
