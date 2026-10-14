FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:0.7 /uv /uvx /bin/

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PROJECT_ENVIRONMENT=/opt/venv
WORKDIR /srv

# Dependensi dulu (lapisan ter-cache), sesuai uv.lock.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY . .

EXPOSE 8000
# Migrasi dan seed makanan/faskes idempoten, aman dijalankan tiap start.
CMD ["sh", "-c", "uv run --frozen --no-dev alembic upgrade head && uv run --frozen --no-dev python -m seed.load && uv run --frozen --no-dev uvicorn app.main:app --host 0.0.0.0 --port 8000"]
