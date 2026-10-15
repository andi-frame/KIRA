FROM python:3.12-slim

COPY --from=ghcr.io/astral-sh/uv:0.7 /uv /uvx /bin/

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    UV_COMPILE_BYTECODE=1 UV_LINK_MODE=copy UV_PROJECT_ENVIRONMENT=/opt/venv
WORKDIR /srv

# Dependensi dulu (lapisan ter-cache), sesuai uv.lock.
COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY . .

# Proses aplikasi tidak perlu hak root.
RUN useradd --system --no-create-home kira && chown -R kira /srv
USER kira

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/health/ready', timeout=4).status == 200 else 1)"

# Migrasi dan seed makanan/faskes idempoten, aman dijalankan tiap start.
# --proxy-headers: alamat klien asli dibaca dari penyeimbang beban (Caddy) di depannya.
CMD ["sh", "-c", "uv run --frozen --no-dev alembic upgrade head && uv run --frozen --no-dev python -m seed.load && uv run --frozen --no-dev uvicorn app.main:app --host 0.0.0.0 --port 8000 --proxy-headers --forwarded-allow-ips=*"]
