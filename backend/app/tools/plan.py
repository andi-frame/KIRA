from langchain_core.runnables import RunnableConfig
from langchain_core.tools import tool

from app.services import history, plan as plan_service
from app.tools._ctx import ctx

MAX_HISTORY_DAYS = 7


def _meal_brief(m: dict) -> dict:
    return {"waktu": m["label"], "jam": m.get("time"), "usulan": m.get("title"), "sudah_dimakan": m.get("done", False),
            "kkal": (m.get("totals") or {}).get("kcal"), "alasan": m.get("why")}


def _brief(plan: dict) -> dict:
    ex = plan.get("exercise")
    return {
        "tanggal": plan["date"],
        "energi_kkal": plan["energy"]["kcal"],
        "makan": [_meal_brief(m) for m in plan["meals"]],
        "olahraga": None if not ex else {"menit": ex["minutes"], "jenis": ex.get("activity"), "jam": ex.get("time"),
                                         "alasan": ex["why"], "ditahan": ex.get("blocked", False)},
        "tidur": {"jam_tidur": plan["sleep"]["bedtime"], "target_jam": plan["sleep"]["hours"]},
        "penyesuaian": plan.get("adapted"),
    }


@tool
async def rencana_hari_ini(config: RunnableConfig) -> dict:
    """Usulan hari ini: makan (sarapan, siang, selingan, malam) beserta alasannya, olahraga, dan jam tidur, sudah
    disesuaikan dengan yang dicatat hari ini. Panggil bila pengguna bertanya makan apa, olahraga apa, atau tidur jam
    berapa hari ini. Sampaikan sebagai usulan, jangan mengarang rencana sendiri."""
    user_id, session_factory = ctx(config)
    async with session_factory() as session:
        plan = await plan_service.plan_today(session, user_id)
    return {**_brief(plan), "catatan": plan["disclaimer"]}


@tool
async def rencana_minggu(config: RunnableConfig) -> dict:
    """Usulan 7 hari ke depan (makan, olahraga, tidur per hari). Panggil bila pengguna minta jadwal atau rencana minggu
    ini/besok. Jangan mengarang rencana sendiri."""
    user_id, session_factory = ctx(config)
    async with session_factory() as session:
        week = await plan_service.plan_week(session, user_id)
    return {"hari": [_brief(d) for d in week["days"]], "catatan": week["days"][0]["disclaimer"]}


@tool
async def riwayat_makan(config: RunnableConfig, hari: int = 3) -> dict:
    """Ringkasan makan dan minum beberapa hari terakhir (maks 7) dengan total gula, natrium, lemak, dan kalori per hari.
    Panggil bila pengguna bertanya apa yang sudah dimakan atau bagaimana pola makannya."""
    user_id, session_factory = ctx(config)
    days = max(1, min(int(hari or 3), MAX_HISTORY_DAYS))
    async with session_factory() as session:
        data = await history.meal_history(session, user_id, days)
    return {"hari": [
        {"tanggal": d["date"], "tercatat": d["logged"], "total": d["totals"], "batas": d["limits"],
         "makan": [m["title"] for m in d["meals"]], "minum": [m["title"] for m in d["drinks"]]}
        for d in data["days"]
    ]}
