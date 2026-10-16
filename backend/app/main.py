from contextlib import asynccontextmanager

import logging
import time
import uuid as _uuid

from fastapi import FastAPI, Request, Response, status
from fastapi.responses import JSONResponse
from sqlalchemy import text
from fastapi.middleware.cors import CORSMiddleware

from app.api import account, auth, bp_protocol, dashboard, foods, goals, plan, products, share, chat, family, health, logs, passive, profile, summary, whatsapp
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
for module in (auth, account, bp_protocol, dashboard, foods, goals, plan, share, products, profile, chat, logs, health, whatsapp, family, summary, passive):
    app.include_router(module.router)


log = logging.getLogger("kira.http")


@app.middleware("http")
async def request_id_and_timing(request: Request, call_next) -> Response:
    """Satu id per permintaan (dikembalikan di header) dan satu baris log: metode, jalur, status, durasi. Tanpa isi/query."""
    rid = request.headers.get("x-request-id") or _uuid.uuid4().hex[:12]
    started = time.perf_counter()
    try:
        response = await call_next(request)
    except Exception:
        log.exception("%s %s rid=%s gagal", request.method, request.url.path, rid)
        raise
    response.headers["X-Request-ID"] = rid
    log.info("%s %s %s %.0fms rid=%s", request.method, request.url.path, response.status_code,
             (time.perf_counter() - started) * 1000, rid)
    return response


@app.get("/health")
async def health_check() -> dict[str, str]:
    """Proses hidup. Tidak menyentuh basis data (dipakai pemeriksa 'liveness')."""
    return {"status": "ok"}


@app.get("/health/ready")
async def readiness() -> JSONResponse:
    """Siap melayani: basis data terjangkau. Dipakai penyeimbang beban sebelum mengarahkan lalu lintas."""
    try:
        async with SessionLocal() as session:
            await session.execute(text("select 1"))
    except Exception:  # noqa: BLE001 - alasan apa pun berarti belum siap
        return JSONResponse({"status": "not_ready"}, status_code=status.HTTP_503_SERVICE_UNAVAILABLE)
    return JSONResponse({"status": "ready"})
