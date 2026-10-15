"""Tautan ringkasan untuk dokter: pemilik membuat, melihat, dan mencabut; penerima membuka tanpa akun."""
import uuid

from fastapi import APIRouter, Depends, HTTPException, Response
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.summary import compute_doctor_summary
from app.config import settings
from app.db import get_session
from app.models import ShareLink
from app.security import current_user_id
from app.services import access_log, share, share_page
from app.services.doctor_pdf import build_doctor_pdf
from app.services.trends import build_trends
from app.timeutil import WIB, local_date, utcnow

router = APIRouter(tags=["share"])
# Halaman publik tidak boleh tersimpan di cache perantara atau terindeks mesin pencari.
_PRIVATE = {"Cache-Control": "no-store", "X-Robots-Tag": "noindex, nofollow", "Referrer-Policy": "no-referrer"}


class ShareIn(BaseModel):
    days: int = Field(default=30, ge=1, le=90)
    valid_days: int = Field(default=share.DEFAULT_VALID_DAYS, ge=1, le=share.MAX_VALID_DAYS)


def _out(link: ShareLink, token: str | None = None) -> dict:
    out = {
        "id": str(link.id),
        "days": link.days,
        "created_at": link.created_at.isoformat(),
        "expires_at": link.expires_at.isoformat(),
        "revoked": link.revoked_at is not None,
        "expired": link.expires_at <= utcnow(),
        "open_count": link.open_count,
        "last_opened_at": link.last_opened_at.isoformat() if link.last_opened_at else None,
    }
    if token is not None:
        base = settings.public_base_url.rstrip("/")
        out["url"] = f"{base}/s/{token}"
        out["pdf_url"] = f"{base}/s/{token}/ringkasan.pdf"
    return out


@router.post("/summary/share")
async def create_share(
    body: ShareIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    try:
        link, token = await share.create(session, user_id, days=body.days, valid_days=body.valid_days)
    except share.TooManyLinks:
        raise HTTPException(
            409, f"Sudah ada {share.MAX_ACTIVE_LINKS} tautan aktif. Cabut salah satu dulu sebelum membuat yang baru."
        ) from None
    return _out(link, token)


@router.get("/summary/share")
async def list_shares(
    user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    return {"links": [_out(link) for link in await share.list_links(session, user_id)]}


@router.delete("/summary/share/{link_id}")
async def revoke_share(
    link_id: uuid.UUID, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    if not await share.revoke(session, user_id, link_id):
        raise HTTPException(404, "Tautan tidak ditemukan")
    return {"ok": True}


async def _open(session: AsyncSession, token: str) -> tuple[ShareLink, dict, dict]:
    link = await share.resolve(session, token)
    if link is None:
        raise HTTPException(404, "Tautan tidak berlaku")
    trends = await build_trends(session, link.user_id, link.days)
    summary = await compute_doctor_summary(session, link.user_id, link.days, trends)
    return link, summary, trends


@router.get("/s/{token}", response_class=HTMLResponse)
async def open_share(token: str, session: AsyncSession = Depends(get_session)) -> HTMLResponse:
    try:
        link, summary, _ = await _open(session, token)
    except HTTPException:
        return HTMLResponse(share_page.invalid_page(), status_code=404, headers=_PRIVATE)
    await share.mark_opened(session, link)
    await access_log.record(
        session, link.user_id, kind="share_link", viewer_name="Penerima tautan",
        detail=f"Tautan {local_date(link.created_at).strftime('%d/%m')}",
    )
    expires = link.expires_at.astimezone(WIB).strftime("%d/%m/%Y %H:%M WIB")
    return HTMLResponse(share_page.summary_page(summary, f"/s/{token}/ringkasan.pdf", expires), headers=_PRIVATE)


@router.get("/s/{token}/ringkasan.pdf")
async def open_share_pdf(token: str, session: AsyncSession = Depends(get_session)) -> Response:
    try:
        link, summary, trends = await _open(session, token)
    except HTTPException:
        return HTMLResponse(share_page.invalid_page(), status_code=404, headers=_PRIVATE)
    await share.mark_opened(session, link)
    await access_log.record(
        session, link.user_id, kind="share_link", viewer_name="Penerima tautan",
        detail=f"Tautan {local_date(link.created_at).strftime('%d/%m')}",
    )
    return Response(
        build_doctor_pdf(summary, trends),
        media_type="application/pdf",
        headers={**_PRIVATE, "Content-Disposition": 'inline; filename="ringkasan-kira.pdf"'},
    )
