from langchain_core.runnables import RunnableConfig

from app.core_calc.red_flags import detect_red_flags
from app.graph.state import KiraState
from app.repos import foods as foods_repo
from app.services.extraction import ExtractionError, extract_from_image, extract_from_text
from app.tools._ctx import ctx


async def _catalog_text(config: RunnableConfig) -> str:
    _, session_factory = ctx(config)
    async with session_factory() as session:
        return foods_repo.catalog_prompt(await foods_repo.catalog(session))


async def extract(state: KiraState, config: RunnableConfig) -> dict:
    catalog = await _catalog_text(config)
    try:
        if state.get("image"):
            result = await extract_from_image(state["image"], state.get("image_kind") or "food", catalog)
        else:
            result = await extract_from_text(state["input_text"], catalog)
    except ExtractionError:
        return {"error": "extraction_failed"}

    flag = None
    clinical = result.clinical_result
    if clinical is not None:
        value = clinical.value
        if clinical.kind in {"fasting_glucose", "random_glucose"} and "mg_dl" in value:
            flag = detect_red_flags(glucose_mg_dl=value["mg_dl"])
        elif clinical.kind == "blood_pressure" and "sys" in value and "dia" in value:
            flag = detect_red_flags(bp=(int(value["sys"]), int(value["dia"])))
    update = {"extraction": result.model_dump(), "red_flag": flag.kind if flag else None}
    if flag:
        update["reply"] = flag.message
    return update
