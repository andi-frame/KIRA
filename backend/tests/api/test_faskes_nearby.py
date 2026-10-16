"""GET /faskes/nearby: data peta (OpenStreetMap/Google) dengan tautan Google Maps."""
from app.services import faskes_lookup
from tests.services.test_faskes_lookup import LAT, LNG, OVERPASS


async def test_endpoint_faskes_terdekat_mengembalikan_sumber_dan_tautan(client, auth_headers, monkeypatch):
    async def osm(lat, lng):
        return faskes_lookup.parse_overpass(OVERPASS)

    monkeypatch.setattr(faskes_lookup, "_overpass", osm)
    r = await client.get("/faskes/nearby", params={"lat": LAT, "lng": LNG}, headers=auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["source"] == "osm" and body["faskes"][0]["name"] == "Puskesmas Dago" and body["search_url"]
