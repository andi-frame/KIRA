import uuid
from typing import Literal

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.logs import log_out
from app.db import get_session, get_session_factory
from app.graph.kira_graph import RunResult, run_kira_graph
from app.schemas.api import ChatIn, ChatOut
from app.security import limit_llm_calls
from app.repos import logs as logs_repo
from app.repos import messages as messages_repo
from app.security import current_user_id
from app.timeutil import local_date, utcnow
from app.services import idempotency
from app.services.stt import SttError, get_stt

router = APIRouter(prefix="/chat", tags=["chat"])

MAX_AUDIO_BYTES = 10 * 1024 * 1024
MAX_IMAGE_BYTES = 8 * 1024 * 1024


async def _out(session: AsyncSession, user_id: uuid.UUID, result: RunResult, transcript: str | None = None) -> ChatOut:
    meals = [log_out(lg, items) for lg, items in await logs_repo.by_ids(session, user_id, result.log_ids)
             if lg.kind == "meal"]
    return ChatOut(reply=result.reply, extraction=result.extraction, red_flag=result.red_flag,
                   log_ids=result.log_ids, tool_calls=result.tool_calls, transcript=transcript, meals=meals)


@router.get("/history")
async def history(
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Obrolan hari ini (satu riwayat per hari). Obrolan hari-hari sebelumnya dibersihkan saat hari berganti.
    Catatan makan yang dibuat dari sebuah balasan ikut dikirim dengan isinya yang TERKINI (bukan salinan lama)."""
    await messages_repo.purge_before_today(session, user_id)
    rows = await messages_repo.today(session, user_id)
    ids = list(dict.fromkeys(i for m in rows for i in ((m.meta or {}).get("log_ids") or [])))
    meals = {str(lg.id): log_out(lg, items) for lg, items in await logs_repo.by_ids(session, user_id, ids) if lg.kind == "meal"}
    return {
        "date": local_date(utcnow()).isoformat(),
        "messages": [
            {"id": str(m.id), "role": m.role, "text": m.content or "", "channel": m.channel,
             "at": m.created_at.isoformat(), "red_flag": (m.meta or {}).get("red_flag"),
             "tool_calls": m.tool_calls or [],
             "meals": [meals[i] for i in ((m.meta or {}).get("log_ids") or []) if i in meals]}
            for m in rows
        ],
    }


@router.delete("/history", status_code=status.HTTP_204_NO_CONTENT)
async def clear_history(
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> None:
    """Hapus obrolan hari ini. Catatan makan/minum/tidur yang sudah tersimpan tidak ikut terhapus."""
    await messages_repo.clear_today(session, user_id)


@router.post("/message", response_model=ChatOut)
async def message(
    body: ChatIn,
    user_id: uuid.UUID = Depends(limit_llm_calls),
    session_factory=Depends(get_session_factory),
    session: AsyncSession = Depends(get_session),
    key: str | None = Depends(idempotency.idempotency_key),
) -> ChatOut:
    # Kiriman ulang dari antrean offline mendapat jawaban yang sama dan tidak dicatat dua kali.
    stored = await idempotency.replay(session, user_id, key)
    if stored is not None:
        return ChatOut(**stored)
    result = await run_kira_graph(str(user_id), "app", input_text=body.text, session_factory=session_factory)
    out = await _out(session, user_id, result)
    await idempotency.remember(session, user_id, key, out.model_dump(mode="json"))
    return out


@router.post("/voice", response_model=ChatOut)
async def voice(
    audio: UploadFile = File(...),
    user_id: uuid.UUID = Depends(limit_llm_calls),
    session_factory=Depends(get_session_factory),
    session: AsyncSession = Depends(get_session),
) -> ChatOut:
    data = await audio.read()
    if not data:
        raise HTTPException(422, "Rekaman kosong, coba rekam lagi.")
    if len(data) > MAX_AUDIO_BYTES:
        raise HTTPException(413, "Rekaman terlalu panjang.")
    try:
        transcript = await get_stt().transcribe(data, audio.filename or "voice.m4a")
    except SttError:
        raise HTTPException(
            status.HTTP_502_BAD_GATEWAY, "Suaramu belum bisa diproses. Coba lagi sebentar lagi ya."
        ) from None
    if not transcript.strip():
        raise HTTPException(422, "Suaranya tidak terdengar jelas, coba rekam lagi.")
    result = await run_kira_graph(
        str(user_id), "app", input_text=transcript, source="voice", session_factory=session_factory
    )
    return await _out(session, user_id, result, transcript)


@router.post("/photo", response_model=ChatOut)
async def photo(
    kind: Literal["food", "receipt", "label", "result"],
    image: UploadFile = File(...),
    user_id: uuid.UUID = Depends(limit_llm_calls),
    session_factory=Depends(get_session_factory),
    session: AsyncSession = Depends(get_session),
) -> ChatOut:
    data = await image.read()
    if not data:
        raise HTTPException(422, "Fotonya kosong, coba ambil lagi.")
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(413, "Foto terlalu besar.")
    result = await run_kira_graph(
        str(user_id), "app", image=data, image_kind=kind, session_factory=session_factory
    )
    return await _out(session, user_id, result)
