import uuid
from typing import Literal

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status

from app.db import get_session_factory
from app.graph.kira_graph import RunResult, run_kira_graph
from app.schemas.api import ChatIn, ChatOut
from app.security import current_user_id
from app.services.stt import SttError, get_stt

router = APIRouter(prefix="/chat", tags=["chat"])

MAX_AUDIO_BYTES = 10 * 1024 * 1024
MAX_IMAGE_BYTES = 8 * 1024 * 1024


def _out(result: RunResult, transcript: str | None = None) -> ChatOut:
    return ChatOut(reply=result.reply, extraction=result.extraction, red_flag=result.red_flag,
                   log_ids=result.log_ids, tool_calls=result.tool_calls, transcript=transcript)


@router.post("/message", response_model=ChatOut)
async def message(
    body: ChatIn, user_id: uuid.UUID = Depends(current_user_id), session_factory=Depends(get_session_factory)
) -> ChatOut:
    result = await run_kira_graph(str(user_id), "app", input_text=body.text, session_factory=session_factory)
    return _out(result)


@router.post("/voice", response_model=ChatOut)
async def voice(
    audio: UploadFile = File(...),
    user_id: uuid.UUID = Depends(current_user_id),
    session_factory=Depends(get_session_factory),
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
    return _out(result, transcript)


@router.post("/photo", response_model=ChatOut)
async def photo(
    kind: Literal["food", "receipt", "label", "result"],
    image: UploadFile = File(...),
    user_id: uuid.UUID = Depends(current_user_id),
    session_factory=Depends(get_session_factory),
) -> ChatOut:
    data = await image.read()
    if not data:
        raise HTTPException(422, "Fotonya kosong, coba ambil lagi.")
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(413, "Foto terlalu besar.")
    result = await run_kira_graph(
        str(user_id), "app", image=data, image_kind=kind, session_factory=session_factory
    )
    return _out(result)
