from fastapi import FastAPI

from app.api import auth, profile

app = FastAPI(title="KIRA API")
app.include_router(auth.router)
app.include_router(profile.router)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}
