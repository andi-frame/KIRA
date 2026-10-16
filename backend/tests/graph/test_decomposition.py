"""Pemecahan hidangan saat mencatat: komponen ber-gizi dari tabel foods, id dari model divalidasi, ragu -> abstain."""
import pytest
from sqlalchemy import select

from app.models import Log, LogItem
from tests.core_calc.seed_data import seed_dishes, seed_foods
from tests.graph.fakes import ai
from tests.graph.test_graph import install, run

BASE = {"drinks": [], "sleep": None, "activity": [], "clinical_result": None, "intent": "log"}


async def saved(session_maker, uid):
    async with session_maker() as s:
        log = (await s.execute(select(Log).where(Log.user_id == uid, Log.kind == "meal"))).scalar_one()
        items = (await s.execute(select(LogItem).where(LogItem.log_id == log.id))).scalars().all()
    return log, sorted(items, key=lambda i: i.name)


def expected_total(dish_id, key):
    dish = next(d for d in seed_dishes() if d.id == dish_id)
    return sum(seed_foods()[c.food_id].per100g[key] * c.grams / 100 for c in dish.components)


@pytest.mark.parametrize("item", [{"name": "ayam geprek", "dish_id": "ayam_geprek"},
                                  {"name": "ayam geprek level 3"},  # tanpa id: dicocokkan dengan resep
                                  {"name": "ayam geprek", "dish_id": "ID_KARANGAN", "food_id": "x"}])  # id palsu dibuang
async def test_ayam_geprek_menjadi_empat_komponen_terkelompok(session_maker, make_user, item):
    uid = await make_user()
    install([ai("Tercatat.")], {**BASE, "items": [item]})
    result = await run(uid, session_maker, input_text="aku makan ayam geprek")
    log, items = await saved(session_maker, uid)
    assert len(items) == 4 and {i.group_name for i in items} == {"Ayam geprek"}
    assert all(i.food_id and i.kcal is not None for i in items)
    # total = jumlah komponen, dihitung ulang langsung dari tabel (bukan dari model)
    for key in ("kcal", "sugar_g", "sodium_mg", "fat_g"):
        assert sum(getattr(i, key) for i in items) == pytest.approx(expected_total("ayam_geprek", key))
    assert log.extracted["resolved"][0]["dish_id"] == "ayam_geprek" and len(result.log_ids) == 1


async def test_porsi_hidangan_menskalakan_semua_komponen(session_maker, make_user):
    uid = await make_user()
    dish = next(d for d in seed_dishes() if d.id == "ayam_geprek")
    install([ai("Tercatat.")], {**BASE, "items": [{"name": "ayam geprek", "dish_id": "ayam_geprek",
                                                   "portion_g_guess": dish.serving_g / 2}]})
    await run(uid, session_maker, input_text="setengah porsi ayam geprek")
    _, items = await saved(session_maker, uid)
    assert sum(i.portion_g for i in items) == pytest.approx(dish.serving_g / 2)
    assert sum(i.kcal for i in items) == pytest.approx(expected_total("ayam_geprek", "kcal") / 2)


async def test_komponen_dari_model_divalidasi_dan_yang_tidak_dikenal_abstain(session_maker, make_user):
    uid = await make_user()
    item = {"name": "nasi bakar cakalang", "components": [
        {"name": "nasi", "food_id": "nasi_putih", "portion_g_guess": 150},  # id valid
        {"name": "timun", "food_id": "id_karangan", "portion_g_guess": 30},  # id palsu -> cocokkan nama
        {"name": "cakalang suwir pedas", "portion_g_guess": 50},  # tidak dikenal -> abstain
    ]}
    install([ai("Tercatat.")], {**BASE, "items": [item]})
    await run(uid, session_maker, input_text="makan nasi bakar cakalang")
    log, items = await saved(session_maker, uid)
    by_name = {i.name: i for i in items}
    assert by_name["nasi"].food_id == "nasi_putih" and by_name["nasi"].kcal == pytest.approx(
        seed_foods()["nasi_putih"].per100g["kcal"] * 1.5)
    assert by_name["timun"].food_id == "timun"
    unknown = by_name["cakalang suwir pedas"]
    assert unknown.food_id is None and unknown.kcal is None and unknown.portion_g == 50  # tidak ada angka karangan
    assert {i.group_name for i in items} == {"nasi bakar cakalang"}
    assert log.extracted["resolved"][0]["from_model"] is True


async def test_makanan_tunggal_tetap_satu_item(session_maker, make_user):
    uid = await make_user()
    install([ai("Tercatat.")], {**BASE, "items": [{"name": "nasi goreng", "food_id": "nasi_goreng"}]})
    await run(uid, session_maker, input_text="makan nasi goreng")
    _, items = await saved(session_maker, uid)
    assert len(items) == 1 and items[0].food_id == "nasi_goreng" and items[0].group_name is None


async def test_hidangan_tak_dikenal_tanpa_komponen_tidak_menghasilkan_angka(session_maker, make_user):
    uid = await make_user()
    chat, _ = install([ai("Tercatat.")], {**BASE, "items": [{"name": "kapurung", "portion_g_guess": 300}]})
    await run(uid, session_maker, input_text="makan kapurung")
    _, items = await saved(session_maker, uid)
    assert len(items) == 1 and items[0].kcal is None and items[0].food_id is None
    context = " ".join(str(m.content) for m in chat.seen[0])
    assert "kapurung" in context and "belum ada di database gizi" in context


async def test_katalog_dikirim_ke_model_ekstraksi(session_maker, make_user):
    uid = await make_user()
    _, extract = install([ai("Tercatat.")], {**BASE, "items": [{"name": "ayam geprek"}]})
    await run(uid, session_maker, input_text="ayam geprek")
    system = extract.calls[0][0].content
    assert "KATALOG HIDANGAN" in system and "ayam_geprek|Ayam geprek: ayam goreng tepung, nasi putih" in system
    assert "timun|Timun" in system and "JANGAN mengisi angka gizi" in system


async def test_tidur_yang_hanya_disebut_lamanya_tersimpan(session_maker, make_user):
    uid = await make_user()
    install([ai("Tercatat.")], {**BASE, "items": [], "sleep": {"hours": 5}})
    result = await run(uid, session_maker, input_text="semalam tidur cuma 5 jam")
    async with session_maker() as s:
        log = (await s.execute(select(Log).where(Log.user_id == uid, Log.kind == "sleep"))).scalar_one()
    assert log.extracted["hours"] == 5 and len(result.log_ids) == 1


async def test_minuman_yang_juga_masuk_items_tidak_dihitung_dua_kali(session_maker, make_user):
    # terukur pada model sungguhan: es teh manis muncul di items (food_id dari katalog) dan di drinks
    uid = await make_user()
    install([ai("Tercatat.")], {**BASE, "items": [{"name": "ayam geprek", "dish_id": "ayam_geprek"},
                                                  {"name": "es teh manis", "food_id": "es_teh_manis"}],
                                "drinks": [{"name": "es teh manis", "size": "gelas", "count": 1}]})
    await run(uid, session_maker, input_text="ayam geprek sama es teh manis")
    _, items = await saved(session_maker, uid)
    assert {i.group_name for i in items} == {"Ayam geprek"} and len(items) == 4
    async with session_maker() as s:
        drinks = (await s.execute(select(Log).where(Log.user_id == uid, Log.kind == "drink"))).scalars().all()
    assert len(drinks) == 1


async def test_pemecahan_dari_model_tidak_ditimpa_hidangan_yang_hanya_mirip(session_maker, make_user):
    """Regresi: "nasi ayam katsu scrambled egg" dicatat sebagai nasi ayam goreng + sambal bawang + lalapan, padahal pengguna tidak
    menyebutnya, karena "nasi ayam" adalah alias hidangan lain. Pemecahan dari model harus dipakai."""
    uid = await make_user()
    item = {"name": "nasi ayam katsu scrambled egg", "components": [
        {"name": "nasi putih", "food_id": "nasi_putih", "portion_g_guess": 150},
        {"name": "ayam katsu", "food_id": "ayam_goreng_tepung", "portion_g_guess": 100},
        {"name": "scrambled egg", "food_id": "telur_dadar", "portion_g_guess": 60},
    ]}
    install([ai("Tercatat.")], {**BASE, "items": [item]})
    await run(uid, session_maker, input_text="aku makan nasi, ayam katsu, dan scrambled egg")
    log, items = await saved(session_maker, uid)
    assert {i.name for i in items} == {"nasi putih", "ayam katsu", "scrambled egg"}
    assert {i.food_id for i in items} == {"nasi_putih", "ayam_goreng_tepung", "telur_dadar"}
    assert not {"sambal_bawang", "lalapan", "ayam_goreng"} & {i.food_id for i in items}
    assert log.extracted["resolved"][0].get("from_model") is True and log.extracted["resolved"][0].get("dish_id") is None


async def test_nama_persis_hidangan_tetap_menang_atas_komponen_model(session_maker, make_user):
    uid = await make_user()
    item = {"name": "ayam geprek", "components": [{"name": "ayam", "food_id": "ayam_goreng", "portion_g_guess": 100}]}
    install([ai("Tercatat.")], {**BASE, "items": [item]})
    await run(uid, session_maker, input_text="makan ayam geprek")
    log, items = await saved(session_maker, uid)
    assert len(items) == 4 and log.extracted["resolved"][0]["dish_id"] == "ayam_geprek"


async def test_tanpa_pemecahan_model_dan_kata_makanan_lain_abstain_bukan_menebak(session_maker, make_user):
    uid = await make_user()
    install([ai("Tercatat.")], {**BASE, "items": [{"name": "nasi ayam katsu scrambled egg"}]})
    await run(uid, session_maker, input_text="makan nasi ayam katsu scrambled egg")
    log, items = await saved(session_maker, uid)
    assert [i.name for i in items] == ["nasi ayam katsu scrambled egg"] and items[0].kcal is None  # belum terhitung, tidak karangan
