#!/usr/bin/env sh
# GenUI shop backend (port 8010) - see docs/architecture.md
cd "$(dirname "$0")" || exit 1
if [ ! -f .env ]; then
  echo "[ERROR] .env not found. Copy .env.example to .env first." >&2
  exit 1
fi
exec python -m uvicorn app.main:app --host 127.0.0.1 --port 8010
