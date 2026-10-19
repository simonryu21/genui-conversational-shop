"""환경설정 로드 — .env 단일 소스 + .env.local 오버레이 (설계: docs/architecture.md §9).

로드 순서:
  1. .env        — 공용 설정 (예시: .env.example). 실파일은 .gitignore.
  2. .env.local  — 개인/회사 전용 오버레이 (예시: .env.bedrock.example). 같은 키가 있으면 .env를 덮어쓴다.
                   회사 Bedrock 계정·게이트웨이 주소·프로파일명처럼 저장소에 올리면 안 되는 값은 여기에만 둔다.
                   (.gitignore의 `.env.*` 규칙으로 커밋되지 않는다)
"""
import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

BASE_DIR = Path(__file__).resolve().parents[1]
load_dotenv(BASE_DIR / ".env")
load_dotenv(BASE_DIR / ".env.local", override=True)

# LLM 공급자별 기본 모델 ID
#   anthropic : Anthropic API 직결 (ANTHROPIC_API_KEY)
#   bedrock   : AWS Bedrock 경유 (표준 AWS 자격증명 체인) — 글로벌 추론 프로파일 ID
_DEFAULT_MODEL = {
    "anthropic": "claude-opus-5-5",
    "bedrock": "global.anthropic.claude-opus-5-5",
}

# 데모 언어 — 시스템 프롬프트의 응답 언어와 서버 안내 문구. FE 설정 메뉴가 요청마다 보내는 lang이 우선.
SUPPORTED_LANGUAGES = ("ko", "en")

_provider = os.environ.get("LLM_PROVIDER", "anthropic").strip().lower()
if _provider not in _DEFAULT_MODEL:
    raise ValueError(f"LLM_PROVIDER must be one of {sorted(_DEFAULT_MODEL)}, got {_provider!r}")

_language = os.environ.get("DEMO_LANGUAGE", "en").strip().lower() or "en"
if _language not in SUPPORTED_LANGUAGES:
    raise ValueError(f"DEMO_LANGUAGE must be one of {SUPPORTED_LANGUAGES}, got {_language!r}")


@dataclass(frozen=True)
class Settings:
    database_url: str = os.environ["DATABASE_URL"]
    llm_provider: str = _provider
    claude_model_id: str = os.environ.get("CLAUDE_MODEL_ID") or _DEFAULT_MODEL[_provider]
    llm_effort: str = os.environ.get("LLM_EFFORT", "medium")
    demo_language: str = _language
    # bedrock 전용
    bedrock_region: str = os.environ.get("BEDROCK_REGION", "us-east-1")
    aws_profile: str | None = os.environ.get("AWS_PROFILE") or None
    # 회사 내부 Bedrock 게이트웨이/프록시 엔드포인트 (비우면 AWS 공식 엔드포인트) — .env.local에만 기재
    bedrock_base_url: str | None = os.environ.get("BEDROCK_BASE_URL") or None
    port: int = int(os.environ.get("PORT", "8010"))
    log_dir: Path = BASE_DIR / "logs" / "turns"


settings = Settings()


def resolve_language(requested: str | None) -> str:
    """요청의 lang(FE 설정 메뉴)을 검증해 반환, 없거나 미지원이면 .env 기본값."""
    if requested:
        code = requested.strip().lower()
        if code in SUPPORTED_LANGUAGES:
            return code
    return settings.demo_language
