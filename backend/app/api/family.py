"""Fitur keluarga: pengguna mengundang anggota keluarga dan memilih apa yang dibagikan.

Anggota HANYA melihat ringkasan yang diizinkan (status check-in dan ada/tidaknya anjuran cek), tanpa detail
makanan, hasil lab, atau skor risiko, dan tidak bisa mengubah data pemilik. Akses bisa dicabut kapan saja.
"""
import uuid

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.models import FamilyLink, Log, User
from app.security import current_user_id
from app.services import risk
from app.timeutil import local_date, utcnow

router = APIRouter(prefix="/family", tags=["family"])
DEFAULT_PERMISSIONS = {"checkin_status": True, "check_reminders": True}
QUIET_DAYS = 3


class Permissions(BaseModel):
    checkin_status: bool = True
    check_reminders: bool = True


class InviteIn(BaseModel):
    phone: str = Field(pattern=r"^\+?\d{8,15}$")
    permissions: Permissions | None = None


class PermissionsPatch(BaseModel):
    checkin_status: bool | None = None
    check_reminders: bool | None = None


def _link_out(link: FamilyLink) -> dict:
    return {
        "id": str(link.id),
        "member_phone": link.member_phone,
        "status": link.status,
        "permissions": {**DEFAULT_PERMISSIONS, **link.permissions},
    }


async def _name(session: AsyncSession, user_id: uuid.UUID) -> str:
    user = await session.get(User, user_id)
    return user.display_name if user and user.display_name else "Anggota keluargamu"


@router.post("/invite")
async def invite(
    body: InviteIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    me = await session.get(User, user_id)
    if body.phone == me.phone:
        raise HTTPException(422, "Kamu tidak bisa mengundang dirimu sendiri.")
    existing = (
        await session.execute(
            select(FamilyLink.id).where(FamilyLink.owner_id == user_id, FamilyLink.member_phone == body.phone)
        )
    ).first()
    if existing:
        raise HTTPException(409, "Nomor ini sudah diundang.")
    member = (await session.execute(select(User).where(User.phone == body.phone))).scalar_one_or_none()
    perms = {**DEFAULT_PERMISSIONS, **(body.permissions.model_dump() if body.permissions else {})}
    link = FamilyLink(
        owner_id=user_id, member_phone=body.phone, member_id=member.id if member else None, permissions=perms
    )
    session.add(link)
    await session.commit()
    await session.refresh(link)
    return _link_out(link)


@router.get("")
async def overview(user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)) -> dict:
    me = await session.get(User, user_id)
    owned = (await session.execute(select(FamilyLink).where(FamilyLink.owner_id == user_id))).scalars().all()
    incoming = (
        await session.execute(
            select(FamilyLink).where(or_(FamilyLink.member_id == user_id, FamilyLink.member_phone == me.phone))
        )
    ).scalars().all()
    invites, watching = [], []
    for link in incoming:
        item = {
            "id": str(link.id),
            "owner_name": await _name(session, link.owner_id),
            "permissions": {**DEFAULT_PERMISSIONS, **link.permissions},
        }
        (invites if link.status == "pending" else watching).append(item)
    return {"members": [_link_out(link) for link in owned], "invites_for_me": invites, "watching": watching}


@router.post("/{link_id}/accept")
async def accept(
    link_id: uuid.UUID, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    me = await session.get(User, user_id)
    link = await session.get(FamilyLink, link_id)
    if link is None or link.status != "pending" or link.member_phone != me.phone or link.owner_id == user_id:
        raise HTTPException(404, "Undangan tidak ditemukan")
    link.member_id, link.status = user_id, "active"
    await session.commit()
    return _link_out(link)


@router.patch("/{link_id}/permissions")
async def change_permissions(
    link_id: uuid.UUID,
    body: PermissionsPatch,
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    link = await session.get(FamilyLink, link_id)
    if link is None or link.owner_id != user_id:
        raise HTTPException(404, "Undangan tidak ditemukan")
    link.permissions = {**DEFAULT_PERMISSIONS, **link.permissions, **body.model_dump(exclude_none=True)}
    await session.commit()
    return _link_out(link)


@router.delete("/{link_id}")
async def end_link(
    link_id: uuid.UUID, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    me = await session.get(User, user_id)
    link = await session.get(FamilyLink, link_id)
    involved = link is not None and (user_id in {link.owner_id, link.member_id} or link.member_phone == me.phone)
    if not involved:
        raise HTTPException(404, "Undangan tidak ditemukan")
    await session.delete(link)
    await session.commit()
    return {"ok": True}


@router.get("/{link_id}/status")
async def shared_status(
    link_id: uuid.UUID, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict:
    link = await session.get(FamilyLink, link_id)
    if link is None or link.status != "active" or link.member_id != user_id:
        raise HTTPException(404, "Tautan tidak ditemukan")
    perms = {**DEFAULT_PERMISSIONS, **link.permissions}
    out: dict = {"owner_name": await _name(session, link.owner_id), "checkin_status": None, "check_reminders": None}
    if perms["checkin_status"]:
        last = (
            await session.execute(select(func.max(Log.occurred_at)).where(Log.user_id == link.owner_id))
        ).scalar_one()
        days = (local_date(utcnow()) - local_date(last)).days if last else None
        quiet = days is not None and days >= QUIET_DAYS
        out["checkin_status"] = {
            "last_checkin_days_ago": days,
            "suggestion": (
                "Sudah beberapa hari belum check-in. Mungkin ini saat yang baik untuk menyapa dan mengajak ngobrol, "
                "tanpa menghakimi."
                if quiet
                else None
            ),
        }
    if perms["check_reminders"]:
        out["check_reminders"] = {"has_open_check": bool(await risk.open_recommendations(session, link.owner_id))}
    return out
