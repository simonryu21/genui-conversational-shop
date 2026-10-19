"""인메모리 세션 저장소 (설계 §8-2 + 2026-08-27 시나리오 변경).

세션이 보관하는 것:
- 대화 히스토리 (캡 + A2UI 축약)
- **장바구니 초안·접수된 주문 (미결제 상태)** — 결제 확정 전에는 DB에 쓰지 않는다.
  FE가 reload하면 새 session_id가 생성되므로 미결제 상태는 자동 소멸 → 헤더는
  실제 DB 포인트로 복귀 (재로그인 시맨틱의 데모 대용).
"""
import re
import threading
import time
from dataclasses import dataclass, field

MEMBER_ID = "m-001"          # 데모 고정 회원
MAX_MESSAGES = 30            # user/assistant 합산 메시지 수 상한
SHRINK_THRESHOLD = 12        # 이 개수를 넘어야 오래된 턴의 A2UI 축약 시작
KEEP_INTACT = 6              # 최근 N개 메시지는 축약하지 않음 (모델의 정답 예시로 유지)
TTL_SECONDS = 3600

_JSON_FENCE = re.compile(r"```json\s*(\{.*?\})\s*```", re.DOTALL)
_SURFACE_ID = re.compile(r'"surfaceId"\s*:\s*"([^"]+)"')


def _shrink_a2ui(text: str) -> str:
    """오래된 assistant 턴의 A2UI JSON 펜스를 한 줄 마커로 축약 (컨텍스트 폭증 방지).

    주의(2026-08-27 실측): 마커가 히스토리에 쌓이면 모델이 이를 UI 표현 방식으로
    모방해 실제 JSON 대신 마커를 출력한다 → 최근 턴은 원문 유지(KEEP_INTACT),
    마커는 자기설명형으로, 시스템 프롬프트에도 모방 금지 명시.
    """
    def repl(m: re.Match) -> str:
        sid = _SURFACE_ID.search(m.group(1))
        return f"<이전 턴의 A2UI JSON 생략됨: {sid.group(1) if sid else 'surface'}>"
    return _JSON_FENCE.sub(repl, text)


@dataclass
class Session:
    session_id: str
    member_id: str = MEMBER_ID
    history: list = field(default_factory=list)   # Anthropic messages 형식
    cart_items: list = field(default_factory=list)  # 세션 단일 장바구니 [{product_id,name,price}]
    orders: dict = field(default_factory=dict)    # order_id(str) → 접수 주문 (미확정 포함)
    lock: threading.Lock = field(default_factory=threading.Lock)
    last_seen: float = field(default_factory=time.time)

    def pending_points(self) -> int:
        """접수됐지만 아직 확정되지 않은 주문들의 포인트 예약분 합계."""
        return sum(o["points_used"] for o in self.orders.values()
                   if o["status"] == "결제 대기")

    def append_and_cap(self, messages: list) -> None:
        self.history = messages
        edited = False   # 히스토리 프리픽스를 건드렸는지 (Opus 5.5 preserved-thinking 대응)
        if len(self.history) > MAX_MESSAGES:
            edited = True
            self.history = self.history[-MAX_MESSAGES:]
            # 히스토리는 반드시 일반 user 텍스트 턴으로 시작해야 한다 —
            # tool_result(user, list content)로 시작하면 API 400 (짝 잃은 tool_use_id)
            while self.history and not (
                self.history[0]["role"] == "user"
                and isinstance(self.history[0].get("content"), str)
            ):
                self.history.pop(0)
        # 히스토리가 충분히 길 때만, 최근 KEEP_INTACT개를 제외한 assistant 턴의 A2UI 축약
        if len(self.history) > SHRINK_THRESHOLD:
            for msg in self.history[:-KEEP_INTACT]:
                if msg["role"] == "assistant" and isinstance(msg["content"], list):
                    for block in msg["content"]:
                        if getattr(block, "type", None) == "text" and "```json" in block.text:
                            edited = True
                            block.text = _shrink_a2ui(block.text)
        # Opus 5.5(2026-10-14 전환)부터 thinking 블록은 "생성 당시의 대화 프리픽스"에 묶인다.
        # 위에서 이전 턴을 잘라내거나 축약했다면 이후 블록은 전부 무효 → 신규 계정은 400.
        # 공식 복구 절차 1(thinking/redacted_thinking 블록 제거, text·tool_use는 유지)을
        # 히스토리를 실제로 편집한 턴에만 적용한다 (짧은 데모 세션에서는 발동하지 않음).
        if edited:
            for msg in self.history:
                if msg["role"] == "assistant" and isinstance(msg["content"], list):
                    kept = [b for b in msg["content"]
                            if getattr(b, "type", None) not in ("thinking", "redacted_thinking")]
                    if kept:
                        msg["content"] = kept


class SessionStore:
    def __init__(self) -> None:
        self._sessions: dict[str, Session] = {}
        self._guard = threading.Lock()

    def get(self, session_id: str) -> Session:
        now = time.time()
        with self._guard:
            expired = [k for k, s in self._sessions.items() if now - s.last_seen > TTL_SECONDS]
            for k in expired:
                del self._sessions[k]
            if session_id not in self._sessions:
                self._sessions[session_id] = Session(session_id)
            s = self._sessions[session_id]
            s.last_seen = now
            return s


store = SessionStore()
