from langchain_core.runnables import RunnableConfig

from app.core_calc.label import LabelFacts, label_totals
from app.core_calc.red_flags import parse_sleep_hours
from app.graph.state import KiraState
from app.repos import foods as foods_repo
from app.repos import logs as logs_repo
from app.repos.logs import ItemData
from app.schemas.extraction import Extraction
from app.services import log_edit, risk
from app.services import medical_records as records_service
from app.services.meal_slot import SLOT_LABELS, infer_meal_slot
from app.services.nutrition_items import item_data, resolve_food_item
from app.timeutil import WIB, utcnow
from app.tools._ctx import ctx

LOGGING_INTENTS = {"log", "result_input"}
SLOT_QUESTION = (
    "Waktu makan untuk catatan '{title}' belum pasti: KIRA mencatatnya sebagai {guess} hanya dari jam {clock}. "
    "Tanyakan SATU pertanyaan singkat: ini sarapan, makan siang, makan malam, atau selingan? (Aplikasi juga menampilkan "
    "pilihannya.) Jangan mengubah catatan sebelum pengguna menjawab."
)


async def save_logs(state: KiraState, config: RunnableConfig) -> dict:
    user_id, session_factory = ctx(config)
    extraction = Extraction.model_validate(state["extraction"])
    source, raw, now = state.get("source", "text"), state.get("input_text"), utcnow()
    notes: list[str] = []
    log_ids: list[str] = []

    async with session_factory() as session:
        catalog = await foods_repo.catalog(session)

        async def add(kind: str, extracted: dict, items: list[logs_repo.ItemData],
                       meal_slot: str | None = None, slot_confirmed: bool = True) -> None:
            log = await logs_repo.add_log(
                session, user_id, kind=kind, source=source, occurred_at=now, extracted=extracted,
                raw_text=raw, items=items, commit=False, meal_slot=meal_slot, slot_confirmed=slot_confirmed,
            )
            log_ids.append(str(log.id))

        is_label = state.get("image_kind") == "label"
        if extraction.intent == "correction":
            # Koreksi atas catatan yang sudah ada: tidak boleh menjadi entri baru (itu membuat catatan dobel).
            if extraction.correction is None:
                notes.append("Pesan ini tampak seperti koreksi tetapi tidak jelas catatan mana yang dimaksud. "
                             "Tanyakan; jangan mencatat entri baru.")
            else:
                outcome = await log_edit.apply_correction(session, user_id, extraction.correction)
                notes.append(outcome.note)
                if outcome.ok and outcome.log_id and extraction.correction.action != "delete":
                    log_ids.append(outcome.log_id)
        elif extraction.intent == "medical_record":
            if extraction.medical_record is None:
                notes.append("Pengguna tampak bercerita soal riwayat medis tetapi isinya tidak jelas. Tanyakan apa yang ingin dicatat.")
            else:
                saved = await records_service.add_from_chat(session, user_id, extraction.medical_record)
                notes.append(saved)
        elif is_label:
            note = await _save_label(add, extraction)
            if note:
                notes.append(note)
        elif extraction.intent in LOGGING_INTENTS:
            # Model kadang memasukkan minuman ke items DAN drinks (katalog memuat minuman): yang di drinks yang dipakai,
            # supaya gulanya tidak terhitung dua kali.
            drink_keys = {d.name.strip().lower() for d in extraction.drinks} | {
                f.id for d in extraction.drinks if (f := catalog.find_food(d.name))}
            food_items = [it for it in extraction.items
                          if it.name.strip().lower() not in drink_keys and (it.food_id or "") not in drink_keys]
            if food_items:
                items, resolved = [], []
                for it in food_items:
                    res = resolve_food_item(it, catalog)
                    items.extend(res.items)
                    notes.extend(res.notes)
                    resolved.append(res.trace)
                stated = next((it.meal_time for it in food_items if it.meal_time), None)
                main_dish = any(_is_main_dish(catalog, it) for it in food_items)
                slot, sure = infer_meal_slot(stated, now, total_kcal=sum(i.kcal or 0 for i in items), main_dish=main_dish)
                if not sure:
                    title = ", ".join(dict.fromkeys(i.group_name or i.name for i in items)) or "makanan"
                    notes.append(SLOT_QUESTION.format(title=title, guess=SLOT_LABELS[slot], clock=now.astimezone(WIB).strftime("%H.%M")))
                await add("meal", {"items": [i.model_dump() for i in food_items], "resolved": resolved}, items,
                          meal_slot=slot, slot_confirmed=sure)
            for drink in extraction.drinks:
                food = catalog.find_food(drink.name)
                if food is None:
                    notes.append(f"Minuman '{drink.name}' belum ada di database gizi; gizinya belum terhitung.")
                await add("drink", {"name": drink.name, "size": drink.size, "count": drink.count},
                          [item_data(drink.name, food, None, multiplier=drink.count)])
            sleep = extraction.sleep
            if sleep and (sleep.bed_time or sleep.wake_time or sleep.hours):
                hours = parse_sleep_hours(sleep.bed_time, sleep.wake_time) if sleep.bed_time and sleep.wake_time else None
                await add("sleep", {**sleep.model_dump(), "hours": hours if hours is not None else sleep.hours}, [])
            for act in extraction.activity:
                await add("activity", act.model_dump(), [])

        clinical = extraction.clinical_result
        # Angka dalam pertanyaan ("kalau gula puasaku 130...") bukan hasil pemeriksaan: jangan disimpan.
        is_result = extraction.intent == "result_input" or state.get("image_kind") == "result"
        if clinical is not None and not is_result:
            notes.append("Ada angka pemeriksaan di pesan ini tetapi bukan laporan hasil, jadi tidak disimpan. "
                         "Minta pengguna memasukkannya lewat Saatnya cek bila memang hasil ukur.")
        elif clinical is not None:
            try:
                await risk.record_result(
                    session, user_id, clinical.kind, clinical.value,
                    source="lab" if state.get("image_kind") == "result" else "self", commit=False,
                )
            except ValueError:
                notes.append("Angka hasil pemeriksaan tidak masuk akal, jadi tidak disimpan. Minta pengguna cek ulang angkanya.")

        if log_ids:
            await session.flush()
            snapshot_state = await risk.compute_risk_state(session, user_id)
            await risk.save_snapshot_if_changed(session, user_id, snapshot_state, commit=False)
            await risk.refresh_check_recommendation(session, user_id, snapshot_state, commit=False)
        await session.commit()
    return {"log_ids": log_ids, "notes": notes}



def _is_main_dish(catalog, item) -> bool:
    dish = catalog.find_dish(item.name, item.dish_id)
    return dish is not None and bool(set(dish.meal_kinds) & {"breakfast", "lunch", "dinner"})


async def _save_label(add, extraction: Extraction) -> str | None:
    """Foto tabel gizi kemasan: simpan angka tercetak (food_id kosong, sumbernya label). Mengembalikan catatan
    sistem bila tidak ada yang tersimpan atau ada yang perlu ditanyakan ke pengguna."""
    label = extraction.label
    if label is None:
        return "Foto label gizi belum terbaca. Minta pengguna memotret ulang tabel informasi nilai gizinya lebih dekat."
    facts = LabelFacts(
        basis=label.basis, serving_g=label.serving_g, servings_consumed=label.servings_consumed,
        sugar_g=label.sugar_g, sodium_mg=label.sodium_mg, fat_g=label.fat_g, kcal=label.kcal,
    )
    try:
        totals = label_totals(facts)
    except ValueError:
        return (f"Angka di label '{label.product_name}' tidak masuk akal (kemungkinan salah baca foto), "
                "jadi tidak disimpan. Minta pengguna memotret ulang label atau menyebutkan angkanya.")
    note = None
    if totals is None:  # label per 100 g tanpa takaran saji: porsi belum bisa dihitung
        totals = {"portion_g": None, "sugar_g": None, "sodium_mg": None, "fat_g": None, "kcal": None}
        note = (f"Label '{label.product_name}' per 100 g tetapi takaran saji tidak terbaca, jadi gizinya belum "
                "terhitung. Tanyakan berapa gram yang dimakan.")
    item = ItemData(name=label.product_name, portion_g=totals["portion_g"], sugar_g=totals["sugar_g"],
                    sodium_mg=totals["sodium_mg"], fat_g=totals["fat_g"], kcal=totals["kcal"])
    kind = "drink" if label.is_drink else "meal"
    extracted = {"label": label.model_dump()}
    if label.is_drink:
        extracted.update({"name": label.product_name, "size": None, "count": 1})
    else:
        extracted["items"] = [{"name": label.product_name}]
    await add(kind, extracted, [item])
    return note
