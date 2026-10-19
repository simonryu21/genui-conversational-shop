"""커밋 전 비밀값·회사 정보 스캔 — staged 파일(기본) 또는 추적 중인 전체 파일(--all).

사용:
  python shop_backend/scripts/check_secrets.py          # git add 된 파일만
  python shop_backend/scripts/check_secrets.py --all    # 추적 중인 모든 파일
  git config core.hooksPath .githooks                   # 커밋마다 자동 실행 (.githooks/pre-commit)

검출 대상:
  - AWS 액세스 키(AKIA/ASIA…), 시크릿 키 대입문, 세션 토큰, Anthropic API 키(sk-ant-…), 개인키 블록
  - 커밋되면 안 되는 경로(.env, .env.local, *.local.*, local/)
  - 저장소 루트의 .secretpatterns.local(미추적)에 적은 회사 고유 문자열 — 한 줄에 하나(회사명·도메인·계정 ID 등)
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

PATTERNS: list[tuple[str, re.Pattern]] = [
    ("AWS access key id", re.compile(r"\b(AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("AWS secret key", re.compile(r"(?i)aws_secret_access_key\s*[=:]\s*['\"]?[A-Za-z0-9/+=]{30,}")),
    ("AWS session token", re.compile(r"(?i)aws_session_token\s*[=:]\s*['\"]?[A-Za-z0-9/+=]{60,}")),
    ("Anthropic API key", re.compile(r"sk-ant-[A-Za-z0-9_-]{20,}")),
    ("Private key block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("AWS account id in ARN", re.compile(r"arn:aws:[a-z0-9-]*:[a-z0-9-]*:\d{12}:")),
]
FORBIDDEN_PATHS = [          # *.example 템플릿은 예외 (아래 is_forbidden)
    re.compile(r"(^|/)\.env(\.[^/]+)?$"),
    re.compile(r"\.local(\.|$)"),
    re.compile(r"(^|/)local/"),
]


def is_forbidden(rel: str) -> bool:
    if rel.endswith(".example"):
        return False
    return any(fp.search(rel) for fp in FORBIDDEN_PATHS)
TEXT_EXT = {".py", ".dart", ".md", ".html", ".txt", ".yaml", ".yml", ".json", ".sql", ".sh",
            ".bat", ".toml", ".cfg", ".ini", ".env", ".example", ".js", ".css", ".lock", ""}


def git_files(all_files: bool) -> list[str]:
    cmd = ["git", "ls-files"] if all_files else ["git", "diff", "--cached", "--name-only", "--diff-filter=ACMR"]
    out = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return [line.strip() for line in out.splitlines() if line.strip()]


def company_terms() -> list[str]:
    f = ROOT / ".secretpatterns.local"
    if not f.exists():
        return []
    return [t.strip() for t in f.read_text(encoding="utf-8").splitlines()
            if t.strip() and not t.startswith("#")]


def main(argv: list[str]) -> int:
    all_files = "--all" in argv
    files = git_files(all_files)
    terms = company_terms()
    hits: list[str] = []

    for rel in files:
        if is_forbidden(rel):
            hits.append(f"{rel}: forbidden path (local/secret file must not be committed)")
        path = ROOT / rel
        if not path.is_file() or path.suffix.lower() not in TEXT_EXT:
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            continue
        for lineno, line in enumerate(text.splitlines(), 1):
            for label, rx in PATTERNS:
                if rx.search(line):
                    hits.append(f"{rel}:{lineno}: {label}")
            for term in terms:
                if term.lower() in line.lower():
                    hits.append(f"{rel}:{lineno}: company term '{term}'")

    if hits:
        print("[check_secrets] BLOCKED - remove these before committing:", file=sys.stderr)
        for h in hits:
            print("  " + h, file=sys.stderr)
        return 1
    print(f"[check_secrets] OK - {len(files)} file(s) scanned, {len(terms)} company term(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
