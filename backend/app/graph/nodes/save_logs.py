from langchain_core.runnables import RunnableConfig

from app.core_calc.nutrition import match_food
from app.core_calc.red_flags import parse_sleep_hours
from app.graph.state import KiraState
from app.repos import foods as foods_repo
from app.repos import logs as logs_repo
from app.schemas.extraction import Extraction
from app.services import risk
from app.services.nutrition_items import item_data
from app.timeutil import utcnow
from app.tools._ctx import ctx

LOGGING_INTENTS = {"log", "result_input"}


async def save_logs(state: KiraState, config: RunnableConfig) -> dict:
    user_id, session_factory = ctx(config)
    extraction = Extraction.model_validate(state["extraction"])
    source, raw, now = state.get("source", "text"), state.get("input_text"), utcnow()
    notes: list[str] = []
    log_ids: list[str] = []

    async with session_factory() as session:
        foods = await foods_repo.all_foods(session)

        async def add(kind: str, extracted: dict, items: list[logs_repo.ItemData]) -> None:
            log = await logs_repo.add_log(
                session, user_id, kind=kind, source=source, occurred_at=now, extracted=extracted,
                raw_text=raw, items=items, commit=False,
            )
            log_ids.append(str(log.id))

        if extraction.intent in LOGGING_INTENTS:
            if extraction.items:
                items = []
                for it in extraction.items:
                    food = match_food(it.name, foods)
                    if food is None:
                        notes.append(f"Makanan '{it.name}' belum ada di database gizi; gizinya belum terhitung.")
                    items.append(item_data(it.name, food, it.portion_g_guess))
                await add("meal", {"items": [i.model_dump() for i in extraction.items]}, items)
            for drink in extraction.drinks:
                food = match_food(drink.name, foods)
                if food is None:
                    notes.append(f"Minuman '{drink.name}' belum ada di database gizi; gizinya belum terhitung.")
                await add("drink", {"name": drink.name, "size": drink.size, "count": drink.count},
                          [item_data(drink.name, food, None, multiplier=drink.count)])
            sleep = extraction.sleep
            if sleep and (sleep.bed_time or sleep.wake_time):
                hours = parse_sleep_hours(sleep.bed_time, sleep.wake_time) if sleep.bed_time and sleep.wake_time else None
                await add("sleep", {**sleep.model_dump(), "hours": hours}, [])
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
            snapshot_state = await risk.compute_risk_state(session, user_id)
            await risk.save_snapshot(session, user_id, snapshot_state, commit=False)
            await risk.refresh_check_recommendation(session, user_id, snapshot_state, commit=False)
        await session.commit()
    return {"log_ids": log_ids, "notes": notes}

