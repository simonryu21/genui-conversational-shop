@echo off
rem GenUI shop backend (port 8010) - see docs/architecture.md
cd /d %~dp0
if not exist .env (
  echo [ERROR] .env not found. Copy .env.example to .env first.
  exit /b 1
)
python -m uvicorn app.main:app --host 127.0.0.1 --port 8010
