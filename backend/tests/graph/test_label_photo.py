from sqlalchemy import text

from app.services.whatsapp import photo_kind
from tests.graph.fakes import ai
from tests.graph.test_graph import _reset_models, count, install, run  # noqa: F401

PNG = b"\x89PNG\r\n\x1a\n" + b"0" * 32


def label(**kw) -> dict:
    base = {"product_name": "Teh Kotak Jasmine", "is_drink": True, "basis": "per_serving", "serving_g": 250,
            "servings_consumed": 1, "sugar_g": 24, "sodium_mg": 50, "fat_g": 0, "kcal": 100}
    return {"items": [], "drinks": [], "intent": "log", "label": {**base, **kw}}


async def items(session_maker):
    async with session_maker() as s:
        rows = (await s.execute(text("select name, portion_g, sugar_g, sodium_mg, kcal, food_id from log_items"))).all()
        logs = (await s.execute(text("select kind, source from logs"))).all()
    return rows, logs


async def test_label_minuman_tersimpan_dengan_angka_tercetak_bukan_estimasi(session_maker, make_user):
    uid = await make_user()
    install([ai("Tercatat.")], label())
    result = await run(uid, session_maker, image=PNG, image_kind="label")
    assert result.log_ids
    rows, logs = await items(session_maker)
    assert logs == [("drink", "photo_label")]
    name, portion, sugar, sodium, kcal, food_id = rows[0]
    assert (name, portion, sugar, sodium, kcal, food_id) == ("Teh Kotak Jasmine", 250, 24, 50, 100, None)


async def test_label_makanan_per_100g_diskalakan_dengan_takaran_dan_jumlah_sajian(session_maker, make_user):
    uid = await make_user()
    install([ai("Tercatat.")], label(product_name="Keripik", is_drink=False, basis="per_100g", serving_g=30,
                                      servings_consumed=2, sugar_g=3, sodium_mg=600, fat_g=30, kcal=520))
    await run(uid, session_maker, image=PNG, image_kind="label")
    rows, logs = await items(session_maker)
    assert logs == [("meal", "photo_label")]
    assert float(rows[0][1]) == 60 and abs(float(rows[0][2]) - 1.8) < 1e-9 and float(rows[0][3]) == 360


async def test_item_karangan_model_diabaikan_pada_foto_label(session_maker, make_user):
    uid = await make_user()
    data = label()
    data["items"] = [{"name": "rendang", "portion_g_guess": 70}]
    install([ai("Tercatat.")], data)
    await run(uid, session_maker, image=PNG, image_kind="label")
    rows, _ = await items(session_maker)
    assert [r[0] for r in rows] == ["Teh Kotak Jasmine"]


async def test_label_dengan_angka_mustahil_tidak_disimpan(session_maker, make_user):
    uid = await make_user()
    chat, _ = install([ai("Maaf, angkanya sepertinya salah baca.")], label(sugar_g=900))
    result = await run(uid, session_maker, image=PNG, image_kind="label")
    assert result.log_ids == []
    assert await count(session_maker, "logs") == 0
    assert "tidak masuk akal" in " ".join(str(m.content) for m in chat.seen[0])


async def test_label_per_100g_tanpa_takaran_hanya_nama_dan_dicatat_catatannya(session_maker, make_user):
    uid = await make_user()
    chat, _ = install([ai("Takarannya berapa?")], label(basis="per_100g", serving_g=None))
    result = await run(uid, session_maker, image=PNG, image_kind="label")
    rows, _ = await items(session_maker)
    assert result.log_ids and rows[0][2] is None
    seen = " ".join(str(m.content) for m in chat.seen[0])
    assert "takaran" in seen.lower()


async def test_foto_label_tanpa_data_label_tidak_menyimpan_apa_pun(session_maker, make_user):
    uid = await make_user()
    install([ai("Labelnya belum terbaca.")], {"items": [], "drinks": [], "intent": "log"})
    result = await run(uid, session_maker, image=PNG, image_kind="label")
    assert result.log_ids == []


def test_keterangan_foto_label_dikenali_sebelum_kata_lab():
    assert photo_kind("ini label gizinya") == "label"
    assert photo_kind("info gizi kemasan") == "label"
    assert photo_kind("hasil lab") == "result"
