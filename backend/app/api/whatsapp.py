"""Kanal WhatsApp (prototype, bot Baileys tidak resmi): tautan akun dan webhook pesan masuk.

Webhook dilindungi shared secret. Semua pesan memakai run_kira_graph yang sama dengan aplikasi.
"""
import base64
import binascii
import hmac
import uuid

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_session, get_session_factory
from app.graph.kira_graph import run_kira_graph
from app.models.whatsapp import WaOutbox
from app.security import current_user_id
from app.services import whatsapp as wa
from app.services.stt import SttError, get_stt
from app.timeutil import utcnow

router = APIRouter(tags=["whatsapp"])
MAX_MEDIA_BASE64 = 14 * 1024 * 1024


class WaIn(BaseModel):
    jid: str
    text: str | None = None
    media_type: str | None = None  # image | audio
    media: str | None = None  # base64


def require_bot(x_bot_secret: str = Header(default="")) -> None:
    if not settings.bot_secret:
        raise HTTPException(503, "Kanal WhatsApp belum diaktifkan.")
    if not hmac.compare_digest(x_bot_secret, settings.bot_secret):
        raise HTTPException(401, "Rahasia bot salah.")


@router.post("/whatsapp/link-code")
async def link_code(
    user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    return {"code": await wa.create_link_code(session, user_id), "expires_in_min": 15}


@router.post("/webhooks/whatsapp", dependencies=[Depends(require_bot)])
async def inbound(
    body: WaIn,
    session: AsyncSession = Depends(get_session),
    session_factory=Depends(get_session_factory),
) -> dict:
    code = wa.parse_link_code(body.text)
    if code is not None:
        user = await wa.redeem_link_code(session, code, body.jid)
        if user is None:
            return {"reply": wa.BAD_CODE_REPLY}
        name = f", {user.display_name}" if user.display_name else ""
        return {"reply": f"Beres! Nomor ini sudah tertaut ke akun KIRA-mu{name}. "
                         "Ceritakan makan, minum, dan tidurmu hari ini ya."}

    user_id = await wa.linked_user_id(session, body.jid)
    if user_id is None:
        return {"reply": wa.NOT_LINKED_REPLY}

    kwargs: dict = {"session_factory": session_factory}
    if body.media and len(body.media) > MAX_MEDIA_BASE64:
        raise HTTPException(413, "Media terlalu besar.")
    try:
        raw = base64.b64decode(body.media) if body.media else None
    except (binascii.Error, ValueError):
        raise HTTPException(422, "Media tidak valid.") from None

    if body.media_type == "audio" and raw:
        try:
            transcript = await get_stt().transcribe(raw, "wa-voice.ogg")
        except SttError:
            return {"reply": "Voice note-nya belum bisa kuproses. Coba kirim lagi atau ketik saja ya."}
        if not transcript.strip():
            return {"reply": "Suaranya kurang jelas terdengar. Coba rekam lagi ya."}
        kwargs.update(input_text=transcript, source="voice")
    elif body.media_type == "image" and raw:
        kwargs.update(image=raw, image_kind=wa.photo_kind(body.text))
    elif body.text and body.text.strip():
        kwargs.update(input_text=body.text)
    else:
        return {"reply": wa.EMPTY_REPLY}

    result = await run_kira_graph(str(user_id), "whatsapp", **kwargs)
    return {"reply": wa.shorten(result.reply)}


@router.get("/webhooks/whatsapp/outbox", dependencies=[Depends(require_bot)])
async def outbox(session: AsyncSession = Depends(get_session)) -> dict:
    rows = (
        await session.execute(
            select(WaOutbox).where(WaOutbox.sent_at.is_(None)).order_by(WaOutbox.created_at).limit(50)
        )
    ).scalars().all()
    return {"messages": [{"id": str(r.id), "jid": r.jid, "text": r.text, "kind": r.kind} for r in rows]}


@router.post("/webhooks/whatsapp/outbox/{message_id}/ack", dependencies=[Depends(require_bot)])
async def ack(message_id: uuid.UUID, session: AsyncSession = Depends(get_session)) -> dict:
    row = await session.get(WaOutbox, message_id)
    if row is None:
        raise HTTPException(404, "Pesan tidak ditemukan")
    row.sent_at = utcnow()
    await session.commit()
    return {"ok": True}

