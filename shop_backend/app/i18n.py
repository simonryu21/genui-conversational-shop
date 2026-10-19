"""서버가 사용자에게 직접 내려보내는 안내 문구 (SSE error/chunk) — 언어별.

모델 응답 언어는 prompts.system_prompt(lang)이 담당하고, 여기는 모델을 거치지 않는
서버 생성 문구(오류·재시도 안내)만 모은다. 키가 없으면 KeyError가 나도록 두어 누락을 바로 드러낸다.
"""

MESSAGES: dict[str, dict[str, str]] = {
    "ko": {
        "session_busy": "이 세션의 이전 턴이 아직 처리 중입니다.",
        "server_error": "서버 오류: {error}",
        "refusal": "안전상의 이유로 이 요청에는 답변할 수 없어요.",
        "tool_rounds_exceeded": "도구 호출이 {max}회를 초과해 중단했어요.",
        "transient_retry": "▸ `일시적 오류({error}) — 재시도 {attempt}/2`  \n",
        "llm_error": "LLM 호출 오류: {error}",
        "anthropic_key_hint": ("Anthropic API 키가 없거나 유효하지 않습니다. "
                               "shop_backend/.env의 ANTHROPIC_API_KEY를 확인한 뒤 서버를 재시작하세요."),
        "aws_creds_hint": ("AWS 자격증명이 없거나 만료되었습니다. "
                           "AWS_PROFILE 또는 액세스 키 환경변수(.env.local)를 갱신한 뒤 다시 시도하세요."),
    },
    "en": {
        "session_busy": "The previous turn of this session is still being processed.",
        "server_error": "Server error: {error}",
        "refusal": "I can't help with this request for safety reasons.",
        "tool_rounds_exceeded": "Stopped after more than {max} tool-call rounds.",
        "transient_retry": "▸ `transient error ({error}) — retry {attempt}/2`  \n",
        "llm_error": "LLM call failed: {error}",
        "anthropic_key_hint": ("The Anthropic API key is missing or invalid. "
                               "Check ANTHROPIC_API_KEY in shop_backend/.env and restart the server."),
        "aws_creds_hint": ("AWS credentials are missing or expired. "
                           "Refresh AWS_PROFILE or the access-key variables (.env.local) and try again."),
    },
}


def msg(lang: str, key: str, **kwargs) -> str:
    table = MESSAGES.get(lang) or MESSAGES["en"]
    return table[key].format(**kwargs)
