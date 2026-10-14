from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api import auth, chat, family, health, logs, profile, summary, whatsapp
from app.config import settings, validate_settings
from app.db import SessionLocal
from app.scheduler import build_scheduler

validate_settings(settings)

@asynccontextmanager
async def lifespan(_: FastAPI):
    scheduler = build_scheduler(SessionLocal) if settings.scheduler_enabled else None
    if scheduler:
        scheduler.start()
    yield
    if scheduler:
        scheduler.shutdown(wait=False)


app = FastAPI(title="KIRA API", lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in settings.cors_origins.split(",") if o.strip()],
    allow_methods=["*"],
    allow_headers=["*"],
)
for module in (auth, profile, chat, logs, health, whatsapp, family, summary):
    app.include_router(module.router)


@app.get("/health")
async def health_check() -> dict[str, str]:
    return {"status": "ok"}
