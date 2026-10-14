from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings

from app.api import auth, chat, health, logs, profile

app = FastAPI(title="KIRA API")
app.add_middleware(
    CORSMiddleware,
    allow_origins=[o.strip() for o in settings.cors_origins.split(",") if o.strip()],
    allow_methods=["*"],
    allow_headers=["*"],
)
for module in (auth, profile, chat, logs, health):
    app.include_router(module.router)


@app.get("/health")
async def health_check() -> dict[str, str]:
    return {"status": "ok"}
