import uuid

from fastapi import APIRouter, Depends, Query
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.repos import foods as foods_repo
from app.security import current_user_id

router = APIRouter(prefix="/foods", tags=["foods"])


@router.get("/search")
async def search_foods(
    q: str = Query(min_length=1, max_length=80),
    limit: int = Query(default=8, ge=1, le=8),
    _: uuid.UUID = Depends(current_user_id),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Saran makanan/hidangan untuk koreksi komponen yang belum terhitung ("maksudmu ...?")."""
    return {"query": q, "results": await foods_repo.search(session, q, limit)}
