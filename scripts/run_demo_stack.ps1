# Menjalankan stack demo KIRA lokal: Postgres, API (DEMO_CACHE aktif), dan Flutter web statis.
# Prasyarat: Docker, venv backend (backend\.venv), Flutter SDK di C:\src\flutter, dan build web sudah dibuat:
#   flutter build web --release --dart-define=API_URL=http://localhost:8000
# Pakai: powershell -File scripts\run_demo_stack.ps1
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

docker compose up -d db | Out-Null
$py = Join-Path $root "backend\.venv\Scripts\python.exe"

Push-Location backend
& $py -m alembic upgrade head
& $py -m seed.load
& $py -m seed.raka --reset
Pop-Location

$env:DEMO_CACHE = "true"
Start-Process -FilePath $py -ArgumentList "-m", "uvicorn", "app.main:app", "--port", "8000" `
  -WorkingDirectory (Join-Path $root "backend") -WindowStyle Hidden
Start-Process -FilePath $py -ArgumentList "-m", "http.server", "8080", "--directory", (Join-Path $root "app\build\web") -WindowStyle Hidden

Write-Output "API:  http://localhost:8000/health"
Write-Output "Web:  http://localhost:8080   (login Raka: 081234567890 / PIN 123456, data dummy)"
