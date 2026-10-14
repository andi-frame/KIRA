from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.repos import users
from app.schemas.auth import Credentials, TokenOut
from app.security import create_token, hash_pin, verify_pin

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=TokenOut)
async def register(body: Credentials, session: AsyncSession = Depends(get_session)) -> TokenOut:
    user = await users.create(session, body.phone, hash_pin(body.pin))
    if user is None:
        raise HTTPException(status.HTTP_409_CONFLICT, "Nomor sudah terdaftar")
    return TokenOut(access_token=create_token(user.id))


@router.post("/login", response_model=TokenOut)
async def login(body: Credentials, session: AsyncSession = Depends(get_session)) -> TokenOut:
    user = await users.get_by_phone(session, body.phone)
    if user is None or not verify_pin(body.pin, user.pin_hash):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED, "Nomor atau PIN salah")
    return TokenOut(access_token=create_token(user.id))
