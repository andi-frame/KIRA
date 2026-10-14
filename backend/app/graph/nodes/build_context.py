import json

from langchain_core.messages import AIMessage, HumanMessage, SystemMessage
from langchain_core.runnables import RunnableConfig

from app.graph.prompts import MODE_NOTES, SYSTEM_PROMPT
from app.graph.state import KiraState
from app.repos import logs as logs_repo
from app.repos import messages as messages_repo
from app.repos import profiles, summaries
from app.services import risk
from app.timeutil import WIB
from app.tools._ctx import ctx


def _log_line(log, items) -> str:
    when = log.occurred_at.astimezone(WIB).strftime("%d/%m %H:%M")
    if log.kind in {"meal", "drink"}:
        names = ", ".join(i.name for i in items) or "-"
        return f"- {when} {log.kind}: {names}"
    return f"- {when} {log.kind}: {json.dumps(log.extracted, ensure_ascii=False)}"


def render_context(profile, state, summary, recent, older, extraction, notes, recommendation) -> str:
    parts = [
        "PROFIL: " + json.dumps(profile.model_dump(mode="json", exclude_none=True), ensure_ascii=False),
        "STATE KESEHATAN: " + json.dumps(
            {
                "mode": state.mode,
                "kategori_risiko_diabetes_perkiraan": [state.category_low, state.category_high],
                "profil_lengkap": not state.needs_profile,
                "kategori_tensi_terakhir": state.last_bp_category,
                "rekomendasi_cek_aktif": recommendation,
            },
            ensure_ascii=False,
        ),
        "(Angka risiko/gizi/target: panggil tool, jangan diambil dari teks ini.)",
        "RINGKASAN MINGGUAN: " + (summary.summary_text if summary and summary.summary_text else "belum ada"),
        "LOG 72 JAM TERAKHIR:\n" + ("\n".join(_log_line(lg, it) for lg, it in recent) or "- kosong"),
    ]
    if older:
        parts.append("LOG LAMA YANG RELEVAN:\n" + "\n".join(
            f"- {lg.occurred_at.astimezone(WIB):%d/%m} {lg.kind}: {lg.raw_text}" for lg in older))
    if extraction:
        parts.append("BARU DICATAT DARI PESAN INI: " + json.dumps(extraction, ensure_ascii=False))
    if notes:
        parts.append("CATATAN SISTEM:\n" + "\n".join(f"- {n}" for n in notes))
    return "\n".join(parts)


async def build_context(state: KiraState, config: RunnableConfig) -> dict:
    user_id, session_factory = ctx(config)
    extraction = state.get("extraction")
    text = state.get("input_text")
    if state.get("image"):
        text = f"(Pengguna mengirim foto {state.get('image_kind') or 'makanan'}.) " + (text or "")
    query = (text or "").strip()

    async with session_factory() as session:
        profile = await profiles.get(session, user_id)
        risk_state = await risk.compute_risk_state(session, user_id)
        summary = await summaries.latest(session, user_id)
        recent = await logs_repo.since(session, user_id, hours=72)
        older = await logs_repo.search_older(session, user_id, query)
        history = await messages_repo.last(session, user_id, n=8)
        open_recs = await risk.open_recommendations(session, user_id)
    recommendation = (
        {"jenis_cek": open_recs[0].test_kind, "alasan": open_recs[0].reason} if open_recs else None
    )
    system = SystemMessage(SYSTEM_PROMPT.format(mode=risk_state.mode, mode_note=MODE_NOTES.get(risk_state.mode, "")))
    context = SystemMessage(
        render_context(profile, risk_state, summary, recent, older, extraction, state.get("notes", []), recommendation)
    )
    past = [HumanMessage(m.content or "") if m.role == "user" else AIMessage(m.content or "") for m in history]
    return {"messages": [system, context, *past, HumanMessage(query)]}
