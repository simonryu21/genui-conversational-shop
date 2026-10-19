"""턴별 JSONL 증적 (설계 §11) — logs/turns/YYYYMMDD.jsonl."""
import json
import threading
from datetime import datetime

from .config import settings

_lock = threading.Lock()


def log_turn(record: dict) -> None:
    settings.log_dir.mkdir(parents=True, exist_ok=True)
    record = {"ts": datetime.now().isoformat(timespec="seconds"), **record}
    path = settings.log_dir / f"{datetime.now():%Y%m%d}.jsonl"
    line = json.dumps(record, ensure_ascii=False, default=str)
    with _lock, path.open("a", encoding="utf-8") as f:
        f.write(line + "\n")
