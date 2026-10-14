from math import asin, cos, radians, sin, sqrt

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Faskes


def haversine_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    dlat, dlng = radians(lat2 - lat1), radians(lng2 - lng1)
    a = sin(dlat / 2) ** 2 + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlng / 2) ** 2
    return 6371.0 * 2 * asin(sqrt(a))


async def nearby(session: AsyncSession, lat: float, lng: float, limit: int = 5) -> list[dict]:
    rows = (await session.execute(select(Faskes))).scalars().all()
    ranked = sorted(
        (
            {"id": r.id, "name": r.name, "kind": r.kind, "address": r.address, "lat": r.lat, "lng": r.lng,
             "distance_km": round(haversine_km(lat, lng, r.lat, r.lng), 2)}
            for r in rows
        ),
        key=lambda f: f["distance_km"],
    )
    return ranked[:limit]
