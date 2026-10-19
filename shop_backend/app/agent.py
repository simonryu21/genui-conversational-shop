"""에이전트 턴 실행 — Claude 스트리밍 + 수동 tool loop (설계 §6).

run_turn은 (event, data) 튜플을 yield하는 동기 제너레이터다:
  ("chunk", str)  — FE의 A2uiTransportAdapter.addChunk에 그대로 들어갈 텍스트 조각
  ("error", str)  — 사용자에게 보여줄 오류
routes가 이를 SSE로 인코딩하고, 종료 시 done 이벤트(잔여 포인트)를 붙인다.
"""
import json
import time
from typing import Generator, Iterable

import anthropic

from .config import settings
from .i18n import msg
from .llm import credential_error_hint, get_client
from .prompts import system_prompt
from .sessions import Session
from .tools import TOOL_SCHEMAS, execute_tool, summarize_input
from .turn_log import log_turn

MAX_TOOL_ROUNDS = 8  # 폭주 방지 상한 (통상 1~3회)

# 프롬프트 캐시: tools(불변) → system(언어별 불변) 프리픽스 끝에 breakpoint 1개
_SYSTEM_BLOCKS: dict[str, list[dict]] = {}


def _system_blocks(lang: str) -> list[dict]:
    if lang not in _SYSTEM_BLOCKS:
        _SYSTEM_BLOCKS[lang] = [{"type": "text", "text": system_prompt(lang),
                                 "cache_control": {"type": "ephemeral"}}]
    return _SYSTEM_BLOCKS[lang]


def _user_content(message: dict) -> str:
    if message.get("type") == "ui_action":
        return "[UI_ACTION] " + message.get("interaction", "")
    return message.get("text", "")


def run_turn(session: Session, message: dict, lang: str = "en") -> Generator[tuple[str, str], None, None]:
    """한 턴 실행. lang(ko/en)은 시스템 프롬프트의 응답 언어와 서버 안내 문구를 정한다 —
    FE 설정 메뉴 값이 요청마다 오며, 세션 중간에 바뀌어도 다음 턴부터 적용된다."""
    started = time.time()
    user_content = _user_content(message)
    messages = [*session.history, {"role": "user", "content": user_content}]

    tool_calls_log: list[dict] = []
    text_len = 0
    usage_last = None
    stop_reason = None
    error_text = None

    def _is_transient(e: Exception) -> bool:
        # (Bedrock) 스트림 도중 비-200 예외 이벤트(스로틀링·일시 오류)가 오면
        # SDK 디코더가 ValueError("Bad response code, ...")를 던진다 (실측).
        if isinstance(e, ValueError) and "Bad response code" in str(e):
            return True
        return isinstance(e, (anthropic.APIConnectionError,
                              anthropic.RateLimitError,
                              anthropic.InternalServerError))

    try:
        client = get_client()
        for _round in range(MAX_TOOL_ROUNDS + 1):
            resp = None
            for attempt in range(3):
                emitted = False
                try:
                    with client.messages.stream(
                        model=settings.claude_model_id,
                        max_tokens=16000,
                        thinking={"type": "adaptive"},
                        output_config={"effort": settings.llm_effort},
                        system=_system_blocks(lang),
                        tools=TOOL_SCHEMAS,
                        messages=messages,
                    ) as stream:
                        for text in stream.text_stream:
                            emitted = True
                            text_len += len(text)
                            yield ("chunk", text)
                        resp = stream.get_final_message()
                    break
                except Exception as e:
                    # 이미 텍스트를 내보낸 뒤라면 재시도 시 중복 출력되므로 포기
                    if emitted or attempt >= 2 or not _is_transient(e):
                        raise
                    yield ("chunk", msg(lang, "transient_retry", error=type(e).__name__, attempt=attempt + 1))
                    time.sleep(2.0 * (attempt + 1))

            usage_last = resp.usage
            stop_reason = resp.stop_reason
            messages.append({"role": "assistant", "content": resp.content})

            if resp.stop_reason == "refusal":
                yield ("error", msg(lang, "refusal"))
                break

            if resp.stop_reason == "pause_turn":
                continue  # 같은 히스토리로 재요청하면 이어서 진행

            tool_uses = [b for b in resp.content if b.type == "tool_use"]
            if not tool_uses:
                break

            # 실제 도구 실행 — trace 라인은 진짜 tool_use 이벤트에서 생성 (설계 §5)
            yield ("chunk", "\n")
            results = []
            for tu in tool_uses:
                t0 = time.time()
                result, is_error = execute_tool(tu.name, tu.input, session)
                ms = int((time.time() - t0) * 1000)
                tool_calls_log.append({
                    "name": tu.name, "input": tu.input,
                    "is_error": is_error, "ms": ms, "result_size": len(result),
                })
                mark = "⚠" if is_error else "▸"
                yield ("chunk", f"{mark} `{summarize_input(tu.name, tu.input)}`  \n")
                results.append({
                    "type": "tool_result",
                    "tool_use_id": tu.id,
                    "content": result,
                    **({"is_error": True} if is_error else {}),
                })
            yield ("chunk", "\n")
            # 병렬 tool_use여도 결과는 반드시 한 user 메시지로 묶어 반환
            messages.append({"role": "user", "content": results})
        else:
            yield ("error", msg(lang, "tool_rounds_exceeded", max=MAX_TOOL_ROUNDS))

        session.append_and_cap(messages)

    except Exception as e:
        error_text = f"{type(e).__name__}: {e}"
        hint = credential_error_hint(e, lang)
        yield ("error", hint or msg(lang, "llm_error", error=error_text))

    finally:
        log_turn({
            "session_id": session.session_id,
            "lang": lang,
            "user_input": user_content[:500],
            "tool_calls": tool_calls_log,
            "assistant_text_len": text_len,
            "stop_reason": stop_reason,
            "error": error_text,
            "usage": usage_last.model_dump() if usage_last is not None else None,
            "latency_ms": int((time.time() - started) * 1000),
        })


def sse_encode(event: str, data: str) -> str:
    """SSE 프레임 인코딩 — data 내 개행은 멀티 data: 라인으로."""
    lines = "".join(f"data: {line}\n" for line in data.split("\n"))
    return f"event: {event}\n{lines}\n"


def iter_sse(events: Iterable[tuple[str, str]]) -> Generator[str, None, None]:
    for event, data in events:
        yield sse_encode(event, data)
