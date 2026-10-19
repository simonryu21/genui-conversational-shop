"""HTTP 엔드포인트 — POST /api/chat (SSE), GET /api/health (설계 §8)."""
import queue
import threading

from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from . import db
from .agent import run_turn, sse_encode
from .config import resolve_language, settings
from .i18n import msg
from .sessions import store

router = APIRouter()

PING_INTERVAL = 15  # 초 — thinking 구간 프록시 idle timeout 방어 (설계 §8-1)


class ChatMessage(BaseModel):
    type: str  # "text" | "ui_action"
    text: str | None = None
    interaction: str | None = None


class ChatRequest(BaseModel):
    session_id: str
    message: ChatMessage
    lang: str | None = None  # "ko" | "en" — FE 설정 메뉴 값. 없으면 .env DEMO_LANGUAGE


@router.post("/api/chat")
def chat(req: ChatRequest) -> StreamingResponse:
    session = store.get(req.session_id)
    lang = resolve_language(req.lang)
    if not session.lock.acquire(blocking=False):
        raise HTTPException(409, msg(lang, "session_busy"))

    q: queue.Queue = queue.Queue(maxsize=1000)
    _DONE = object()

    def produce() -> None:
        try:
            for item in run_turn(session, req.message.model_dump(), lang):
                q.put(item)
        except Exception as e:  # run_turn 밖 예외도 error 이벤트로 (스레드 침묵사 방지)
            q.put(("error", msg(lang, "server_error", error=f"{type(e).__name__}: {e}")))
        finally:
            q.put(_DONE)

    threading.Thread(target=produce, daemon=True).start()

    def stream():
        try:
            while True:
                try:
                    item = q.get(timeout=PING_INTERVAL)
                except queue.Empty:
                    yield ": ping\n\n"
                    continue
                if item is _DONE:
                    break
                yield sse_encode(*item)
            # 성공/오류 불문 done으로 턴 종료 보장 — FE isProcessing 해제 (설계 §8-1)
            points = db.current_points(session.member_id)
            yield sse_encode("done", f'{{"points": {points}}}')
        finally:
            session.lock.release()

    return StreamingResponse(stream(), media_type="text/event-stream",
                             headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"})


@router.get("/api/member")
def member() -> dict:
    """FE가 화면 진입 시 헤더 포인트를 초기화하는 데 사용 (데모: m-001 고정)."""
    from .sessions import MEMBER_ID
    return db.get_member(MEMBER_ID)


@router.get("/api/health")
def health() -> dict:
    out: dict = {
        "llm_provider": settings.llm_provider,
        "model": settings.claude_model_id,
        "effort": settings.llm_effort,
        "language": settings.demo_language,
    }

    try:
        with db.pool.connection() as conn:
            out["products"] = conn.execute("SELECT count(*) AS c FROM products").fetchone()["c"]
        out["db"] = "ok"
    except Exception as e:
        out["db"] = f"error: {e}"

    if settings.llm_provider == "anthropic":
        import os
        out["anthropic_api_key"] = "set" if os.environ.get("ANTHROPIC_API_KEY") else "missing"
    else:
        try:
            import boto3
            sts = boto3.Session(profile_name=settings.aws_profile).client(
                "sts", region_name=settings.bedrock_region
            )
            ident = sts.get_caller_identity()
            out["aws_creds"] = "ok"
            out["aws_arn"] = ident.get("Arn", "")
        except Exception as e:
            out["aws_creds"] = f"error: {e} — AWS 자격증명(AWS_PROFILE/액세스 키, .env.local)을 확인하세요"
        if settings.bedrock_base_url:
            out["bedrock_base_url"] = "set"  # 회사 게이트웨이 주소는 노출하지 않는다
    return out
