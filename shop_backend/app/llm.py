"""Claude 클라이언트 생성 단일 지점 (설계 §6).

LLM_PROVIDER=anthropic (기본) : Anthropic API 직결 — .env의 ANTHROPIC_API_KEY 사용.
LLM_PROVIDER=bedrock          : AWS Bedrock 경유 — 표준 AWS 자격증명 체인
                                (AWS_PROFILE 또는 AWS_ACCESS_KEY_ID/… 환경변수, BEDROCK_REGION).
                                회사 내부 게이트웨이를 거치면 BEDROCK_BASE_URL, 사내 CA는 SSL_CERT_FILE,
                                프록시는 HTTPS_PROXY — 전부 .env.local(미추적)에만 둔다.

두 클라이언트는 messages.stream 인터페이스가 같으므로 agent.py는 공급자를 모른다.
"""
import anthropic

from .config import settings
from .i18n import msg

_client: anthropic.Anthropic | anthropic.AnthropicBedrock | None = None


def get_client() -> anthropic.Anthropic | anthropic.AnthropicBedrock:
    global _client
    if _client is None:
        if settings.llm_provider == "bedrock":
            kwargs: dict = {"aws_region": settings.bedrock_region}
            if settings.aws_profile:
                kwargs["aws_profile"] = settings.aws_profile
            if settings.bedrock_base_url:
                kwargs["base_url"] = settings.bedrock_base_url
            _client = anthropic.AnthropicBedrock(**kwargs)
        else:
            _client = anthropic.Anthropic()  # ANTHROPIC_API_KEY 환경변수 사용
    return _client


def credential_error_hint(exc: Exception, lang: str = "en") -> str | None:
    """인증/자격증명 계열 오류면 사용자 안내 문구를 반환."""
    text = f"{type(exc).__name__}: {exc}"
    if settings.llm_provider == "anthropic":
        if (isinstance(exc, anthropic.AuthenticationError)
                or "api_key" in text.lower() or "ANTHROPIC_API_KEY" in text):
            return msg(lang, "anthropic_key_hint")
        return None
    for marker in ("ExpiredToken", "InvalidClientTokenId", "UnrecognizedClient",
                   "credential", "Credential", "NoCredentials",
                   "security token", "expired"):
        if marker in text:
            return msg(lang, "aws_creds_hint")
    return None
