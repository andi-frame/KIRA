# Menjalankan stack demo KIRA lokal: Postgres, API (DEMO_CACHE aktif), dan Flutter web statis.
# Prasyarat: Docker, uv (https://docs.astral.sh/uv/), dan build web sudah dibuat:
#   cd app; flutter build web --release --dart-define=API_URL=http://localhost:8000
# Pakai: powershell -File scripts\run_demo_stack.ps1
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

docker compose up -d db | Out-Null

Push-Location backend
uv sync                                  # membuat/menyelaraskan .venv dari pyproject.toml + uv.lock
uv run alembic upgrade head
uv run python -m seed.load
uv run python -m seed.raka --reset       # Raka kembali ke keadaan awal agar demo bisa diulang
Pop-Location

$env:DEMO_CACHE = "true"
Start-Process -FilePath "uv" -ArgumentList "run", "uvicorn", "app.main:app", "--port", "8000" `
  -WorkingDirectory (Join-Path $root "backend") -WindowStyle Hidden
Start-Process -FilePath "uv" -ArgumentList "run", "python", "-m", "http.server", "8080", "--directory", (Join-Path $root "app\build\web") `
  -WorkingDirectory (Join-Path $root "backend") -WindowStyle Hidden

Write-Output "API:  http://localhost:8000/health"
Write-Output "Web:  http://localhost:8080   (login Raka: 081234567890 / PIN 123456, data dummy)"
