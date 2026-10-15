import uuid

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.ratelimit import login_limiter
from app.repos import users
from app.schemas.auth import Credentials, LoginIn, TokenOut, UsernameIn
from app.security import create_token, current_user_id, hash_pin, verify_pin

router = APIRouter(prefix="/auth", tags=["auth"])

DUPLICATE_MESSAGE = {"phone": "Nomor sudah terdaftar", "username": "Nama pengguna sudah dipakai"}


@router.post("/register", response_model=TokenOut)
async def register(body: Credentials, session: AsyncSession = Depends(get_session)) -> TokenOut:
    try:
        user = await users.create(session, body.phone, hash_pin(body.pin), body.username)
    except users.DuplicateError as exc:
        raise HTTPException(status.HTTP_409_CONFLICT, DUPLICATE_MESSAGE[exc.field]) from None
    return TokenOut(access_token=create_token(user.id))


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
    return TokenOut(access_token=create_token(user.id))


@router.put("/username")
async def set_username(
    body: UsernameIn, user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> dict[str, str]:
    """Membuat atau mengganti nama pengguna (akun lama belum punya)."""
    try:
        return {"username": await users.set_username(session, user_id, body.username)}
    except users.DuplicateError:
        raise HTTPException(status.HTTP_409_CONFLICT, DUPLICATE_MESSAGE["username"]) from None
