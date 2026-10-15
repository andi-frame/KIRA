import pytest
from sqlalchemy import text

from app.services import barcode

INDOMIE = "089686010947"  # EAN/UPC sungguhan dengan angka cek valid
PAYLOAD = {
    "status": 1,
    "product": {
        "code": INDOMIE, "product_name": "Indomie Mi Goreng Original", "brands": "Indofood, indomie",
        "quantity": "85 g", "serving_quantity": 85, "categories_tags": ["en:instant-noodles"],
        "nutriments": {"sugars_100g": 7.06, "sodium_100g": 0.3976, "fat_100g": 18.8, "energy-kcal_100g": 470.6},
    },
}
DRINK = {
    "status": 1,
    "product": {
        "code": "8886008101053", "product_name": "Teh Botol Manis", "quantity": "350 ml", "serving_quantity": 350,
        "nutriments": {"sugars_100g": 8.0, "energy-kcal_100g": 33, "salt_100g": 0.05},
    },
}
NO_SUGAR = {"status": 1, "product": {"code": "8886008101053", "product_name": "Air Mineral", "nutriments": {}}}


class FakeOff:
    def __init__(self, payload=None, error: Exception | None = None):
        self.payload, self.error, self.calls = payload, error, []

    async def fetch(self, code: str) -> dict:
        self.calls.append(code)
        if self.error:
            raise self.error
        return self.payload if self.payload is not None else {"status": 0}


@pytest.fixture(autouse=True)
def _reset():
    yield
    barcode.set_client_for_tests(None)


def install(payload=None, error=None) -> FakeOff:
    fake = FakeOff(payload, error)
    barcode.set_client_for_tests(fake)
    return fake


def test_angka_cek_gtin():
    assert barcode.valid_gtin(INDOMIE) and barcode.valid_gtin("8886008101053") and barcode.valid_gtin("96385074")
    assert not barcode.valid_gtin("089686010948") and not barcode.valid_gtin("12345") and not barcode.valid_gtin("abcdefgh")


def test_parse_off_mengubah_satuan_dan_menandai_minuman():
    p = barcode.parse_off(INDOMIE, PAYLOAD)
    assert p.name == "Indomie Mi Goreng Original" and p.brand == "Indofood" and p.serving_g == 85 and not p.is_drink
    assert p.per100g["sodium_mg"] == pytest.approx(397.6) and p.per100g["sugar_g"] == 7.06 and p.complete
    d = barcode.parse_off("8886008101053", DRINK)
    assert d.is_drink and d.per100g["sodium_mg"] == pytest.approx(0.05 / 2.5 * 1000)  # dari garam: natrium = garam/2,5
    assert d.per100g["fat_g"] is None  # tidak tertera: None, bukan 0
    assert barcode.parse_off("x", NO_SUGAR).complete is False
    assert barcode.parse_off("x", {"status": 0}) is None
    assert barcode.parse_off("x", {"status": 1, "product": {"product_name": "  "}}) is None


async def test_cari_produk_mengembalikan_gizi_dan_sumber(client, auth_headers):
    install(PAYLOAD)
    r = await client.get(f"/products/{INDOMIE}", headers=auth_headers)
    assert r.status_code == 200
    body = r.json()
    assert body["name"].startswith("Indomie") and body["complete"] is True and body["serving_g"] == 85
    assert "Open Food Facts" in body["source"] and body["per100g"]["kcal"] == 470.6


async def test_kode_salah_ketik_ditolak_tanpa_memanggil_basis_data_luar(client, auth_headers):
    fake = install(PAYLOAD)
    for bad in ("089686010948", "123", "abcdefghijkl"):
        assert (await client.get(f"/products/{bad}", headers=auth_headers)).status_code == 422
    assert fake.calls == []


async def test_produk_tidak_ada_mengarahkan_ke_foto_label(client, auth_headers):
    install(None)
    r = await client.get(f"/products/{INDOMIE}", headers=auth_headers)
    assert r.status_code == 404 and "foto" in r.json()["detail"].lower()


async def test_hasil_di_cache_sehingga_basis_data_luar_dipanggil_sekali(client, auth_headers):
    fake = install(PAYLOAD)
    await client.get(f"/products/{INDOMIE}", headers=auth_headers)
    await client.get(f"/products/{INDOMIE}", headers=auth_headers)
    assert fake.calls == [INDOMIE]
    miss = install(None)
    await client.get("/products/8886008101053", headers=auth_headers)
    await client.get("/products/8886008101053", headers=auth_headers)
    assert miss.calls == ["8886008101053"]  # "tidak ada" juga di-cache (1 hari)


async def test_basis_data_luar_gagal_memberi_503_ramah(client, auth_headers):
    install(error=barcode.ProductLookupError("Basis data produk belum bisa dihubungi. Coba foto label kemasannya."))
    r = await client.get(f"/products/{INDOMIE}", headers=auth_headers)
    assert r.status_code == 503 and "foto label" in r.json()["detail"]


async def test_catat_dengan_gram_menghitung_gizi_dari_angka_label(client, auth_headers, engine):
    install(PAYLOAD)
    r = await client.post("/logs/barcode", json={"barcode": INDOMIE, "grams": 85}, headers=auth_headers)
    assert r.status_code == 200
    item = r.json()["item"]
    assert r.json()["kind"] == "meal" and item["portion_g"] == 85
    assert item["sugar_g"] == pytest.approx(7.06 * 0.85, rel=1e-3) and item["sodium_mg"] == pytest.approx(397.6 * 0.85, rel=1e-3)
    async with engine.connect() as conn:
        row = (await conn.execute(text("select kind, source from logs"))).one()
        n = (await conn.execute(text("select count(*) from log_items where food_id is null"))).scalar_one()
    assert tuple(row) == ("meal", "barcode") and n == 1  # gizi tercetak, bukan dari tabel pangan


async def test_catat_per_sajian_dan_minuman(client, auth_headers):
    install(DRINK)
    r = await client.post("/logs/barcode", json={"barcode": "8886008101053", "servings": 0.5}, headers=auth_headers)
    assert r.status_code == 200 and r.json()["kind"] == "drink"
    assert r.json()["item"]["portion_g"] == 175 and r.json()["item"]["sugar_g"] == pytest.approx(14.0)


async def test_catat_mengubah_total_gula_hari_ini(client, auth_headers):
    install(DRINK)
    before = (await client.get("/targets/today", headers=auth_headers)).json()
    await client.post("/logs/barcode", json={"barcode": "8886008101053", "servings": 1}, headers=auth_headers)
    after = (await client.get("/targets/today", headers=auth_headers)).json()
    assert after != before


async def test_catat_menolak_masukan_tidak_jelas_atau_tidak_lengkap(client, auth_headers, engine):
    install(DRINK)
    base = {"barcode": "8886008101053"}
    assert (await client.post("/logs/barcode", json={**base}, headers=auth_headers)).status_code == 422  # tanpa jumlah
    assert (await client.post("/logs/barcode", json={**base, "grams": 100, "servings": 1}, headers=auth_headers)).status_code == 422
    assert (await client.post("/logs/barcode", json={**base, "grams": 0}, headers=auth_headers)).status_code == 422
    assert (await client.post("/logs/barcode", json={**base, "servings": 51}, headers=auth_headers)).status_code == 422
    install(NO_SUGAR)
    r = await client.post("/logs/barcode", json={"barcode": "8886008101053", "grams": 100}, headers=auth_headers)
    assert r.status_code == 422 and "belum lengkap" in r.json()["detail"]
    async with engine.connect() as conn:
        assert (await conn.execute(text("select count(*) from logs"))).scalar_one() == 0


async def test_per_sajian_tanpa_takaran_saji_diminta_gram(client, auth_headers):
    payload = {"status": 1, "product": {"product_name": "Biskuit", "nutriments": {"sugars_100g": 20, "energy-kcal_100g": 450}}}
    install(payload)
    r = await client.post("/logs/barcode", json={"barcode": "8886008101053", "servings": 1}, headers=auth_headers)
    assert r.status_code == 422 and "gram" in r.json()["detail"]


async def test_nilai_mustahil_dari_basis_data_luar_ditolak(client, auth_headers):
    payload = {"status": 1, "product": {"product_name": "Salah Input", "nutriments": {"sugars_100g": 250, "energy-kcal_100g": 400}}}
    install(payload)
    r = await client.post("/logs/barcode", json={"barcode": "8886008101053", "grams": 50}, headers=auth_headers)
    assert r.status_code == 422 and "tidak masuk akal" in r.json()["detail"]


async def test_koreksi_porsi_menskalakan_angka_kemasan(client, auth_headers):
    install(PAYLOAD)
    log_id = (await client.post("/logs/barcode", json={"barcode": INDOMIE, "grams": 100}, headers=auth_headers)).json()["log_id"]
    patched = await client.patch(
        f"/logs/{log_id}", json={"items": [{"name": "Indomie Mi Goreng Original", "portion_g": 50}]}, headers=auth_headers
    )
    assert patched.status_code == 200
    item = patched.json()["items"][0]
    assert item["portion_g"] == 50 and item["sugar_g"] == pytest.approx(7.06 * 0.5, rel=1e-3)


async def test_butuh_login(client):
    assert (await client.get(f"/products/{INDOMIE}")).status_code == 401
    assert (await client.post("/logs/barcode", json={"barcode": INDOMIE, "grams": 1})).status_code == 401


async def test_batas_laju_panggilan_keluar_melindungi_dari_pemblokiran_ip():
    client = barcode.HttpOffClient()
    for _ in range(barcode.MAX_CALLS_PER_MINUTE):
        client._throttle()
    with pytest.raises(barcode.ProductLookupError):
        client._throttle()
