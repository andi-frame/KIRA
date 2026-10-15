import uuid
from datetime import date

from sqlalchemy.ext.asyncio import AsyncSession

from app.models import HealthProfile, User
from app.schemas.profile import ProfileIn, ProfileOut
from app.services.account import has_current_consent

PROFILE_COLUMNS = set(ProfileIn.model_fields) - {"display_name"}


def age_from(birth_date: date | None, today: date | None = None) -> int | None:
    if birth_date is None:
        return None
    today = today or date.today()
    return today.year - birth_date.year - ((today.month, today.day) < (birth_date.month, birth_date.day))


async def get(session: AsyncSession, user_id: uuid.UUID) -> ProfileOut:
    user = await session.get(User, user_id)
    profile = await session.get(HealthProfile, user_id)
    data = {c: getattr(profile, c, None) for c in PROFILE_COLUMNS} if profile else {}
    return ProfileOut(
        display_name=user.display_name if user else None,
        username=user.username if user else None,
        mode=user.mode if user else "prevention",
        consented=has_current_consent(user) if user else False,
        age=age_from(data.get("birth_date")),
        **data,
    )


async def update(session: AsyncSession, user_id: uuid.UUID, body: ProfileIn) -> ProfileOut:
    changes = body.model_dump(exclude_unset=True)
    user = await session.get(User, user_id)
    profile = await session.get(HealthProfile, user_id)
    if profile is None:
        profile = HealthProfile(user_id=user_id)
        session.add(profile)
    if "display_name" in changes and user is not None:
        user.display_name = changes.pop("display_name")
    for key, value in changes.items():
        setattr(profile, key, value)
    await session.commit()
    return await get(session, user_id)
