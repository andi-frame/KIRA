import uuid

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from app.db import get_session
from app.security import current_user_id
from app.services.dashboard import build_dashboard

router = APIRouter(tags=["dashboard"])


@router.get("/dashboard")
async def dashboard(user_id: uuid.UUID = Depends(current_user_id), session: AsyncSession = Depends(get_session)) -> dict:
    """Beranda dalam satu panggilan: hari ini (gizi, aktivitas, tidur), minggu ini, sinyal kebiasaan bersumber,
    proyeksi 10 tahun, riwayat skor, target, dan satu langkah berikutnya."""
    return await build_dashboard(session, user_id)
