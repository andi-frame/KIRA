from fastapi import FastAPI

from app.api import auth, chat, health, logs, profile

app = FastAPI(title="KIRA API")
for module in (auth, profile, chat, logs, health):
    app.include_router(module.router)


@app.get("/health")
async def health_check() -> dict[str, str]:
    return {"status": "ok"}
