import uuid
from datetime import UTC, datetime, timedelta

import jwt
from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from app.config import settings

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
