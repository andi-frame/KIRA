import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.db import get_session
from app.ratelimit import login_limiter, otp_limiter
from app.repos import sessions, users
from app.schemas.auth import (
    Credentials,
    LoginIn,
    PinChangeIn,
    PinResetConfirmIn,
    PinResetRequestIn,
    RefreshIn,
    TokenOut,
    UsernameIn,
)
from app.security import create_token, current_user_id, hash_pin, verify_pin
from app.services import account, pin_reset

router = APIRouter(prefix="/auth", tags=["auth"])

DUPLICATE_MESSAGE = {"phone": "Nomor sudah terdaftar", "username": "Nama pengguna sudah dipakai"}


async def issue_tokens(session: AsyncSession, user_id: uuid.UUID) -> TokenOut:
    """Token akses singkat + token penyegar untuk perangkat ini, sehingga pengguna tidak terlempar keluar tiap jam."""
    return TokenOut(
        access_token=create_token(user_id),
        refresh_token=await sessions.start(session, user_id),
        expires_in=settings.jwt_expire_minutes * 60,
    )


@router.post("/register", response_model=TokenOut)
async def register(body: Credentials, session: AsyncSession = Depends(get_session)) -> TokenOut:
    if not body.consent:
        raise HTTPException(
            422,
            "Pendaftaran butuh persetujuanmu atas pemrosesan data kesehatan.",
        )
    try:
        user = await users.create(session, body.phone, hash_pin(body.pin), body.username)
    except users.DuplicateError as exc:
        raise HTTPException(status.HTTP_409_CONFLICT, DUPLICATE_MESSAGE[exc.field]) from None
    await account.record_consent(session, user.id)
    return await issue_tokens(session, user.id)


@router.post("/login", response_model=TokenOut)
async def login(body: LoginIn, session: AsyncSession = Depends(get_session)) -> TokenOut:
    user = await users.get_by_identifier(session, body.identifier)
    # Kunci percobaan per akun (bukan per ketikan), agar berganti antara nama pengguna dan nomor tidak menghindari batas.
    key = str(user.id) if user else f"?{body.identifier.lower()}"
    if login_limiter.blocked(key):
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS,
            "Terlalu banyak percobaan masuk. Coba lagi dalam 15 menit.",
        )
    if user is None or not verify_pin(body.pin, user.pin_hash):
        login_limiter.fail(key)
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Nama pengguna, nomor, atau PIN salah")
    login_limiter.reset(key)
    return await issue_tokens(session, user.id)


@router.post("/refresh", response_model=TokenOut)
async def refresh(body: RefreshIn, session: AsyncSession = Depends(get_session)) -> TokenOut:
    """Menukar token penyegar dengan sepasang token baru; token lama langsung tidak berlaku."""
    rotated = await sessions.rotate(session, body.refresh_token)
    if rotated is None:
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Sesi berakhir. Silakan masuk lagi.")
    user_id, fresh = rotated
    return TokenOut(
        access_token=create_token(user_id), refresh_token=fresh, expires_in=settings.jwt_expire_minutes * 60
    )


@router.post("/logout")
async def logout(body: RefreshIn, session: AsyncSession = Depends(get_session)) -> dict[str, bool]:
    """Mengakhiri sesi di server. Selalu berhasil agar tidak membocorkan apakah token itu pernah ada."""
    await sessions.revoke(session, body.refresh_token)
    return {"ok": True}


@router.put("/username")
async def set_username(
    body: UsernameIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict[str, str]:
    """Membuat atau mengganti nama pengguna (akun lama belum punya)."""
    try:
        return {"username": await users.set_username(session, user_id, body.username)}
    except users.DuplicateError:
        raise HTTPException(status.HTTP_409_CONFLICT, DUPLICATE_MESSAGE["username"]) from None


@router.post("/pin-reset/request")
async def pin_reset_request(body: PinResetRequestIn, session: AsyncSession = Depends(get_session)) -> dict[str, str]:
    """Mengirim kode 6 angka ke WhatsApp yang tertaut. Jawabannya selalu sama agar daftar akun tidak bisa ditebak."""
    user = await users.get_by_identifier(session, body.identifier)
    key = str(user.id) if user else f"?{body.identifier.lower()}"
    if otp_limiter.blocked(key):
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Terlalu banyak permintaan kode. Coba lagi dalam 1 jam.")
    otp_limiter.fail(key)
    await pin_reset.request_code(session, user)
    return {"message": pin_reset.REQUEST_REPLY}


@router.post("/pin-reset/confirm")
async def pin_reset_confirm(body: PinResetConfirmIn, session: AsyncSession = Depends(get_session)) -> dict[str, bool]:
    user = await users.get_by_identifier(session, body.identifier)
    outcome = await pin_reset.confirm(session, user, body.code, body.new_pin)
    if outcome == "locked":
        raise HTTPException(
            status.HTTP_429_TOO_MANY_REQUESTS, "Terlalu banyak kode yang salah. Minta kode baru lalu coba lagi."
        )
    if outcome != "ok":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "Kode salah atau sudah kedaluwarsa.")
    login_limiter.reset(str(user.id))  # kunci masuk karena salah PIN ikut dibuka: pemilik baru saja membuktikan dirinya
    return {"ok": True}


@router.put("/pin")
async def change_pin(
    body: PinChangeIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> TokenOut:
    """Ganti PIN saat sudah masuk. Perangkat lain keluar; perangkat ini mendapat sesi baru."""
    key = str(user_id)
    if login_limiter.blocked(key):
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "Terlalu banyak percobaan. Coba lagi dalam 15 menit.")
    user = await users.get(session, user_id)
    if not verify_pin(body.current_pin, user.pin_hash):
        login_limiter.fail(key)
        raise HTTPException(status.HTTP_403_FORBIDDEN, "PIN saat ini salah")
    login_limiter.reset(key)
    user.pin_hash = hash_pin(body.new_pin)
    await sessions.revoke_all(session, user_id, commit=False)
    await session.commit()
    return await issue_tokens(session, user_id)
