import hashlib
import secrets
import uuid
from datetime import UTC, datetime, timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import settings
from app.ratelimit import llm_daily_limiter, llm_limiter

_hasher = PasswordHasher()
_bearer = HTTPBearer(auto_error=False)
_ALGO = "HS256"


def hash_pin(pin: str) -> str:
    return _hasher.hash(pin)


def verify_pin(pin: str, hashed: str) -> bool:
    try:
        return _hasher.verify(hashed, pin)
    except (VerificationError, InvalidHashError):
        return False


def new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def hash_token(token: str) -> str:
    """Token acak berentropi tinggi, jadi hash cepat sudah cukup (bukan kata sandi buatan manusia)."""
    return hashlib.sha256(token.encode()).hexdigest()


def create_token(user_id: uuid.UUID) -> str:
    exp = datetime.now(UTC) + timedelta(minutes=settings.jwt_expire_minutes)
    return jwt.encode({"sub": str(user_id), "exp": exp}, settings.jwt_secret, algorithm=_ALGO)


def current_user_id(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> uuid.UUID:
    unauthorized = HTTPException(status.HTTP_401_UNAUTHORIZED, "Token tidak valid atau kedaluwarsa")
    if creds is None:
        raise unauthorized
    try:
        payload = jwt.decode(creds.credentials, settings.jwt_secret, algorithms=[_ALGO])
        return uuid.UUID(payload["sub"])
    except (jwt.PyJWTError, KeyError, ValueError):
        raise unauthorized from None


def limit_llm_calls(user_id: uuid.UUID = Depends(current_user_id)) -> uuid.UUID:
    """Dependensi untuk endpoint yang memanggil model bahasa: 20 per menit dan 400 per hari per pengguna."""
    for limiter, message in (
        (llm_limiter, "Terlalu banyak pesan dalam waktu singkat. Tunggu sebentar lalu coba lagi."),
        (llm_daily_limiter, "Batas pesan harian tercapai. Coba lagi besok."),
    ):
        wait = limiter.check(str(user_id))
        if wait is not None:
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS, message, headers={"Retry-After": str(max(1, int(wait) + 1))}
            )
    return user_id
