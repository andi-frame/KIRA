FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
# Migrasi dan seed makanan/faskes idempoten, aman dijalankan tiap start.
CMD ["sh", "-c", "alembic upgrade head && python -m seed.load && uvicorn app.main:app --host 0.0.0.0 --port 8000"]
