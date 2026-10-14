import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.repos import profiles
from app.schemas.profile import ProfileIn, ProfileOut
from app.security import current_user_id

router = APIRouter(prefix="/profile", tags=["profile"])


@router.get("", response_model=ProfileOut)
async def get_profile(
    user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)
) -> ProfileOut:
    return await profiles.get(session, user_id)


@router.put("", response_model=ProfileOut)
async def put_profile(
    body: ProfileIn,
    user_id: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> ProfileOut:
    return await profiles.update(session, user_id, body)
