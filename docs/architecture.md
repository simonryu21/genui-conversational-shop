# 설계 — GenUI 대화형 쇼핑몰 (LLM + PostgreSQL 실연동)

기준일: 2026-10-14 (구현·데모 검증 완료)
관련 문서: [HITL 구현 설명](hitl.md) · [Flutter GenUI SDK 정리](flutter_genui_sdk.md) · [동적성 검증 결과](verification/README.md) · [발표 슬라이드](slides_ko.html)

> **모델 이력.** 설계 당시(2026-08-27)는 Claude Opus 4.8, 2026-10-14부터 Claude Opus 5.5.
> 변경 지점은 `.env`의 `CLAUDE_MODEL_ID` 하나다. 본문에서 "Opus 4.8"로 적힌 수치는 당시 실측 기록이다.

## 1. 목표

`genui_agent/`의 규칙 기반 mock 에이전트(`ScriptedShoppingAgent`)를
**실제 LLM(Claude) + 실제 DB(PostgreSQL)** 로 교체하여,
flutter/genui SDK가 **질의와 LLM 답변에 따라 정말 동적으로 UI를 생성하는지** 검증한다.

핵심 입증 포인트: **UI 코드(Flutter)는 한 줄도 바뀌지 않은 채**, LLM이 DB 조회 결과를 보고
스스로 결정한 A2UI JSON만으로 화면 구성이 달라진다.

```
[FE] Flutter Web (genui 0.10.2 — 렌더링 파이프라인 그대로)
        ↕ HTTP POST + SSE 스트리밍
[BE] Python 에이전트 서버 (FastAPI + Claude)
        ├─ tools: search_products / get_member / … ──→ PostgreSQL (shop_db)
        └─ LLM이 조회 결과로 텍스트 + A2UI JSON 생성 → SSE로 스트림 반환
```

## 2. 변경 범위

| 구성요소 | mock 단계 | 현재 |
|---|---|---|
| 에이전트 | `lib/scripted_agent.dart` (정규식 라우팅, 하드코딩 응답) | BE로 이동 — Claude가 도구 호출 + A2UI 생성 |
| 데이터 | `lib/shop_data.dart` (상수 9개 상품) | PostgreSQL `shop_db` (상품 수백 종 — 실데이터 수집 포함, 회원, 주문, 포인트 원장) |
| 도구 | 텍스트 흔적만 출력 (가짜) | **실제 함수** — SQL 실행 결과가 LLM에 들어감 |
| 렌더링 | `A2uiTransportAdapter` → `SurfaceController` → `Surface` | **변경 없음** (검증의 핵심) |
| 카탈로그 | `lib/shop_catalog.dart` (ProductGrid 등 커스텀 4종) | **변경 없음** — 스키마를 BE 시스템 프롬프트에 복제 |

FE에서 바뀐 것: `ShoppingAgent` 인터페이스 도입 + `RemoteShoppingAgent`(HTTP/SSE 클라이언트,
동일한 `emitChunk` 계약) 추가. 기존 mock은 빌드 플래그(`AGENT_MODE=scripted`)로 유지 — §3-1.

## 3. 디렉토리 구조

### 3-1. FE — `genui_agent/`

에이전트를 인터페이스로 추상화하고, 빌드 플래그로 remote/scripted를 전환한다
(mock 토글 유지 — BE 없이도 오프라인 시연 가능, 스크립트 vs LLM 비교 시연에도 활용).

```
genui_agent/
├── pubspec.yaml                  # genui, json_schema_builder, flutter_markdown_plus, fetch_client
├── lib/
│   ├── main.dart                 # 앱 셸 — 헤더 포인트 표시(세션의 points 게터)
│   ├── chat_session.dart         # 파이프라인 배선 + 채팅 타임라인 상태 (AgentFactory 경유)
│   ├── shop_catalog.dart         # 커스텀 카탈로그 4종 — 동적성 검증의 통제 변수
│   ├── scripted_agent.dart       # mock 모드 전용 (AGENT_MODE=scripted)
│   ├── shop_data.dart            # mock 모드 전용 하드코딩 데이터
│   └── agent/
│       ├── shopping_agent.dart   # abstract ShoppingAgent { handle(ChatMessage); int get points; }
│       ├── agent_factory.dart    # AGENT_MODE(remote 기본 | scripted), BE_URL dart-define
│       ├── remote_agent.dart     # ChatMessage → §8 요청 JSON 직렬화, SSE chunk → emitChunk,
│       │                         #   done 이벤트에서 points 갱신
│       ├── sse_parser.dart       # 표준 SSE 파서 (event:/data: 멀티라인 재조립, ping 코멘트 무시)
│       └── platform_io.dart / platform_web.dart   # 웹에서는 fetch_client로 POST 응답 스트리밍
├── test/
│   ├── scenario_test.dart        # scripted 모드 위젯 테스트 (BE 없이 동작)
│   └── sse_parser_test.dart      # 조각난 청크 재조립 단위 테스트
└── web/
```

실행:
```
flutter run -d chrome                                                    # remote, localhost:8010
flutter run -d chrome --dart-define=BE_URL=http://host:8010
flutter run -d chrome --dart-define=AGENT_MODE=scripted                  # 오프라인 mock
```

### 3-2. BE — `shop_backend/` (포트 8010)

```
shop_backend/
├── .env.example                  # 템플릿 (실파일 .env는 git 제외)
├── .env.bedrock.example          # Bedrock/회사망 오버레이 템플릿 → .env.local로 복사 (git 제외)
├── requirements.txt              # fastapi, uvicorn[standard], anthropic[bedrock], psycopg[binary,pool],
│                                 # python-dotenv, httpx, sse-starlette (+ pytest)
├── run_server.bat / run_server.sh
├── app/
│   ├── config.py                 # .env → .env.local(override) 로드 → Settings (§9 키 전부), resolve_language
│   ├── main.py                   # FastAPI 앱, CORS(*), lifespan에서 DB 풀 해제
│   ├── routes.py                 # POST /api/chat (SSE), GET /api/member, GET /api/health
│   ├── llm.py                    # Claude 클라이언트 생성 1곳 — LLM_PROVIDER=anthropic | bedrock (+BEDROCK_BASE_URL)
│   ├── i18n.py                   # 서버 생성 안내 문구(오류·재시도) ko/en
│   ├── agent.py                  # run_turn(session, message, lang) → (event, data) 제너레이터 (§6 루프)
│   │                             #   tool trace 라인(`▸ ...`) 생성, refusal/인증 오류 → error 이벤트
│   ├── tools.py                  # TOOL_SCHEMAS(strict 8종) + execute_tool 디스패치
│   ├── orders.py                 # 장바구니/접수/확정 — 세션 메모리 vs DB 쓰기 경계 (HITL)
│   ├── db.py                     # psycopg ConnectionPool + 도구별 쿼리 함수, 유일한 쓰기 confirm_order
│   ├── prompts.py                # system_prompt(lang) — 언어별 정적 문자열 (§7 — 요청 간 불변, 캐시 전제)
│   ├── sessions.py               # SessionStore: 히스토리 캡 + A2UI 축약 + 장바구니/주문 메모리 + TTL
│   └── turn_log.py               # 턴별 JSONL 증적 (§11)
├── scripts/
│   ├── init_db.py                # CREATE DATABASE(없으면) → schema.sql → seed.sql (멱등)
│   ├── fetch_seed_data.py        # 참가격 API(선택) + Open Food Facts → products upsert (§4)
│   ├── reset_demo.py             # 주문/원장 정리 + 180,000P 복원
│   ├── schema.sql
│   └── seed.sql                  # 고정 시드 (데모 재현용 9종 + 참치 32종 + 비식품 합성)
├── logs/turns/YYYYMMDD.jsonl     # 증적 (git 제외)
└── tests/test_tools.py           # 도구 단위 테스트 (shop_db 실연동, 쓰기 테스트는 자가 복구)
```

### 3-3. BE 실행/동시성 모델

- `POST /api/chat`은 **sync 제너레이터** + `StreamingResponse`. Anthropic SDK 스트리밍이 sync이므로
  async로 감싸는 대신 FastAPI가 sync 제너레이터를 threadpool에서 돌리는 표준 동작에 맡긴다 —
  데모는 단일 사용자라 이 단순함이 정답.
- DB도 sync psycopg + `ConnectionPool` — 도구 실행이 LLM 루프 안에서 순차 실행되므로 async 불필요.
- 세션당 락: 같은 session_id의 동시 턴 진입 시 409 (FE의 `isProcessing` 가드와 이중 방어).

## 4. DB 설계 (PostgreSQL `shop_db`)

```
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/shop_db
```

`init_db.py`가 `postgres` 기본 DB로 접속해 `shop_db`를 생성한 뒤 스키마·시드를 적용한다 (재실행 안전).

### 스키마 (요지 — 전문은 `scripts/schema.sql`)

```sql
CREATE TABLE members (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, grade TEXT NOT NULL,
    points INT NOT NULL, expiring_pts INT NOT NULL DEFAULT 0, expire_at DATE
);
CREATE TABLE products (
    id TEXT PRIMARY KEY, emoji TEXT NOT NULL, name TEXT NOT NULL, category TEXT NOT NULL,
    price INT NOT NULL, tags TEXT[] NOT NULL DEFAULT '{}', stock INT NOT NULL DEFAULT 100,
    summary TEXT, specs JSONB NOT NULL DEFAULT '{}', repurchase_rate INT, source TEXT
);
CREATE TABLE purchase_history (id SERIAL PRIMARY KEY, member_id TEXT REFERENCES members(id),
    product_id TEXT REFERENCES products(id), purchased_at DATE NOT NULL);
CREATE TABLE orders (id TEXT PRIMARY KEY, member_id TEXT REFERENCES members(id),
    total INT NOT NULL, status TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now());
CREATE TABLE point_ledger (id SERIAL PRIMARY KEY, member_id TEXT REFERENCES members(id),
    delta INT NOT NULL, reason TEXT NOT NULL, created_at TIMESTAMPTZ DEFAULT now());
```

### 시드 데이터 — 3계층 (실데이터 + 합성)

| 소스 | 내용 | 인증 |
|---|---|---|
| **한국소비자원 참가격** ([공공데이터포털](https://www.data.go.kr/data/3043385/openapi.do)) | 실제 생필품 상품명·실판매가 (주 1회 갱신) | 회원가입 + 활용신청(자동승인) → 인증키. **없으면 자동 스킵** |
| **Open Food Facts** ([world.openfoodfacts.org](https://world.openfoodfacts.org)) | 한국 등록 식품 (상품명·브랜드·용량), ODbL | 없음. 상품명 누락 건 필터링 |

1. **고정 시드 (seed.sql)** — mock의 상품 9종을 **id 그대로** 이관(시나리오 재현 보장) + 참치캔 32종 +
   캠핑·가전·리빙·선물 합성 상품 (외부 소스가 식품/생필품 위주라 비식품은 합성으로 보완).
2. **실데이터 수집 (fetch_seed_data.py)** — 카테고리 정규화, 태그 자동 생성(저염·대용량 등 규칙),
   이모지는 키워드 매핑. 재실행 안전(`ON CONFLICT DO UPDATE`, 가격·재고는 기존 값 유지).
3. **회원/이력** — 회원 1명(가상 인물, 180,000P, 120,000P 소멸 예정), 구매 이력 3건(작년 LED 랜턴 포함).

`summary`(추천 근거)는 실데이터에 없으므로 nullable — **LLM이 카드의 reason을 조회 결과에서 직접 작성**한다.
`repurchase_rate`는 시드 시 규칙 기반 의사난수.

참가격 API 메모: 엔드포인트는 **http** 고정(https 404), 응답 XML, 일일 2,000건. Encoding형 키를 URL에 그대로
사용(재인코딩 금지). 신청 직후 `resultCode=90`이면 기관 서버 동기화 지연 — 스크립트가 자동 스킵한다.

## 5. 도구 설계 — "데모의 가짜 trace를 실제 함수로"

모두 `strict: true`(`additionalProperties: false` + `required`)로 선언해 입력 검증을 API 레벨에서 보장.

| 도구 | 구현 (요지) |
|---|---|
| `get_member(member_id)` | members 조회 → 잔여/소멸예정 포인트, D-day, `points_available`(세션 예약분 차감) |
| `get_purchase_history(member_id, category?)` | history JOIN products |
| `search_products(query?, category?, tags?, max_price?, in_stock_only?, sort?, limit)` | `ILIKE`/`tags @>`/가격 필터, 정렬(가격·재구매율), 기본 limit 10, `total_matched` 반환 |
| `get_product_specs(product_ids)` | products.specs JSONB (비교표 소재) |
| `add_to_cart(product_ids)` | **세션 단일 장바구니**에 추가·병합 (DB는 상품 검증 조회만). 전체 장바구니 + `shortfall` 반환 |
| `remove_from_cart(product_ids)` | 장바구니 항목 제거 — CartSummary의 항목별 X 버튼(`removeFromCart`) 연동 |
| `submit_order(payment_method?)` | **세션 메모리 가예약** — 주문번호 발급, 포인트는 예약만. 부족분은 결제수단 지정 필요(없으면 ToolError로 되묻게 함) |
| `confirm_payment(order_id)` | **유일한 DB 쓰기**: 트랜잭션으로 orders + members.points 차감 + point_ledger + purchase_history |

**구매 흐름 3단계**: 담기 → 접수(가예약) → **결제 확정(데모 가상 결제)**.
확정 전 상태는 전부 세션 메모리라 FE reload 시 소멸 → 헤더는 실제 DB 포인트로 복귀.
헤더는 항상 실제 포인트(`points`), 세션 내 예상 잔여는 `points_available`로 구분. 상세는 [hitl.md](hitl.md).

- 도구 결과는 JSON 문자열. 실패 시 `is_error: true` tool_result — LLM이 스스로 복구(재검색 등)하는지도 관찰 대상.
- `▸ \`tool(...)\`` trace 라인은 **BE가 실제 tool_use 이벤트를 관찰해 생성** — 진짜 호출 기록.
- UI 액션(`addToCart`, `checkout`, 모델이 지은 커스텀 액션)에 대한 하드코딩 라우팅은 두지 않는다.
  UI 액션도 LLM에게 전달하고, LLM이 도구 호출 여부를 판단한다 (동적성 검증의 일부).

## 6. LLM 설정

### 공급자 (`LLM_PROVIDER`)

| 값 | 클라이언트 | 인증 | 기본 모델 ID |
|---|---|---|---|
| `anthropic` (기본) | `anthropic.Anthropic()` | `.env`의 `ANTHROPIC_API_KEY` | `claude-opus-5-5` |
| `bedrock` | `anthropic.AnthropicBedrock(aws_region=…, aws_profile=…, base_url=…)` | 표준 AWS 자격증명 체인 (`AWS_PROFILE` 또는 액세스 키 환경변수); 사내 게이트웨이는 `BEDROCK_BASE_URL` | `global.anthropic.claude-opus-5-5` |

두 클라이언트는 `messages.stream` 인터페이스가 같아 `agent.py`는 공급자를 모른다 (`llm.py` 한 곳에서 분기).
Bedrock 테스트용 회사 값(계정·프로파일·게이트웨이·CA)은 `.env.local`(`.env.bedrock.example` 복사, git 제외)에만 둔다 —
`config.py`가 `.env` 뒤에 override로 읽는다. 커밋 전 `scripts/check_secrets.py`(`.githooks/pre-commit`)가 키·계정 ID·금지 경로를 검사한다.
인증 오류는 `credential_error_hint`가 SSE error 이벤트로 사용자 안내 문구를 내려보낸다.

### 파라미터

| 항목 | 값 | 근거 |
|---|---|---|
| 호출 방식 | `client.messages.stream(...)` + 수동 tool loop (최대 8회) | 텍스트 델타를 SSE로 실시간 중계하면서 `stop_reason == "tool_use"` 시 도구 실행 후 루프 재진입 |
| thinking | `thinking: {"type": "adaptive"}` | Opus 4.8은 생략 시 thinking 없이 동작 — 품질 우선. `budget_tokens`는 400 |
| effort | `output_config: {"effort": LLM_EFFORT}` — 기본 `medium` | 속도보다 품질 우선. `.env`로 변경 |
| max_tokens | 16000 | A2UI JSON + 설명 텍스트에 충분 |
| refusal | `stop_reason == "refusal"` → SSE error | |
| pause_turn | 같은 히스토리로 재요청 | |
| 재시도 | 일시 오류(연결·레이트리밋·5xx, Bedrock 스트림 중 비-200 이벤트)는 2회 백오프. **텍스트를 이미 내보낸 뒤면 포기**(중복 출력 방지) | |
| prefill | 사용 안 함 | 4.6+ 계열에서 400 |

루프 구조 (agent.py 요지):

```python
def run_turn(session, message):                       # yield (event, data)
    messages = [*session.history, {"role": "user", "content": user_content}]
    for _ in range(MAX_TOOL_ROUNDS + 1):
        with client.messages.stream(model=MODEL, max_tokens=16000,
                                    thinking={"type": "adaptive"},
                                    output_config={"effort": EFFORT},
                                    system=_SYSTEM, tools=TOOL_SCHEMAS,
                                    messages=messages) as stream:
            for text in stream.text_stream: yield ("chunk", text)
            resp = stream.get_final_message()
        messages.append({"role": "assistant", "content": resp.content})
        if resp.stop_reason == "refusal": yield ("error", ...); break
        tool_uses = [b for b in resp.content if b.type == "tool_use"]
        if not tool_uses: break
        results = [execute_tool(tu) for tu in tool_uses]       # 실제 DB 실행, trace 라인 yield
        messages.append({"role": "user", "content": results})  # 병렬 tool_use여도 한 메시지로
    session.append_and_cap(messages)
```

## 7. 시스템 프롬프트 전략 (prompts.py)

1. **역할**: 복지포인트 쇼핑몰 컨시어지. 반드시 도구로 조회한 실제 데이터만 사용 (카드의 productId는 DB에 존재해야 함).
   **언어**: 템플릿의 `__LANGUAGE_RULE__` 자리에 ko/en 규칙 문장이 들어간다 (`system_prompt(lang)`). 본문(계약·카탈로그·예시)은 한국어 원문 그대로이고,
   en은 "모든 문장·UI 텍스트·action label을 영어로, productId는 그대로, 한글 상품명은 영어 설명 + 괄호 원문"을 지시한다. 언어별 문자열은 하나씩만 존재해 캐시가 유지된다.
2. **A2UI v0.9 계약**: ```json 펜스 안에 `createSurface` → `updateComponents` 순. `createSurface`에
   `catalogId: "com.example.welfare-shop"`, root 컴포넌트 id는 `"root"`, 폼은 `updateDataModel`로 기본값 시딩.
   응답마다 **새 surfaceId**(타임라인에 카드가 쌓임).
3. **카탈로그 스키마**: 커스텀 4종 + 표준 컴포넌트(Column, Text, Button, ChoicePicker)의 필드 명세.
   함정 명시: ChoicePicker 값은 리스트로 도착, Button action context는 `{"path": ...}` 바인딩 가능,
   커스텀 액션의 context에는 반드시 `label`(타임라인 표시용).
4. **판단 지침** (강제 아님): 결과 다수 → ProductGrid / 2~3개 정밀 비교 → ComparisonTable /
   후보 과다 → ChoicePicker 인터뷰 / 단순 조회 → **UI 없이 텍스트만**.
5. **구매 흐름 3단계 규칙** + 접수 응답에 '결제 확정하기' Button을 Column으로 조립하라는 지시.
6. **few-shot 1개**: 캠핑 시나리오 (형식 안정화용).
7. 히스토리의 A2UI 축약 마커(§8-2)를 **모방하지 말라**는 명시 — 실측에서 모델이 마커를 흉내 낸 적이 있어 추가.

시스템 프롬프트는 정적 문자열로 고정(요청마다 불변) — 프롬프트 캐시 적중을 위해 타임스탬프 등 가변 요소 배제.
날짜가 필요한 판단(포인트 소멸 D-day)은 `get_member` 결과의 `expire_in_days`를 쓰게 한다.

### 프롬프트 캐싱

- `system` 블록 끝에 `cache_control: {"type": "ephemeral"}` 1개 — tools(불변) → system(불변) 프리픽스가
  통째로 캐시되어 매 턴·tool loop 매 반복마다 재사용된다.
- 검증: 턴 로그(§11)의 `usage.cache_read_input_tokens` — 2번째 요청부터 0이 아니어야 정상 (실측 매 턴 4,000~6,300).
- 대화 히스토리에는 breakpoint를 두지 않는다 (히스토리 캡 §8-2로 프리픽스가 변형됨).

## 8. API 계약 (BE ↔ FE)

### `POST /api/chat` → `text/event-stream`

```json
{
  "session_id": "s-1724...",
  "lang": "ko" | "en",          // 선택 — FE ⚙ 설정 메뉴 값. 없으면 .env DEMO_LANGUAGE
  "message": {
    "type": "text" | "ui_action",
    "text": "남은 포인트로 겨울 캠핑 용품 추천해줘",
    "interaction": "{\"version\":\"v0.9\",\"action\":{...}}"
  }
}
```

```
event: chunk   data: <A2uiTransportAdapter.addChunk에 그대로 넣을 텍스트 조각>
event: error   data: <사용자에게 보여줄 오류 문구>
event: done    data: {"points": 153000}      // 턴 종료 + 헤더 포인트 갱신
```

- `chunk` 페이로드는 mock과 **동일 계약** (마크다운 + ```json 펜스 A2UI + `▸ tool trace` 라인) — FE 파서 변경 없음.
  SSE data는 라인 기반이므로 청크 내 개행은 `data:` 멀티라인 규칙으로 인코딩.
- CORS는 `*` 허용 (로컬 데모 — `flutter run`이 매번 임의 포트를 쓰므로).

### 8-1. SSE 신뢰성 규칙

- **keepalive**: 15초마다 `: ping` 코멘트 — 프록시/브라우저 idle timeout 방어 (thinking 구간은 수십 초 무데이터).
- **턴 종료 보장**: 성공이든 오류든 스트림은 반드시 `done`으로 끝난다 (`error` → `done`) — FE `isProcessing` 해제가 걸려 있음.
- 생산 스레드에서 `run_turn`을 돌리고 소비 제너레이터가 큐를 읽는다 — 예외도 반드시 error 이벤트로.

### 8-2. 세션 수명주기 (인메모리)

- FE가 앱 시작 시 `session_id` 생성, 턴마다 동일 값. 새 세션 = 페이지 새로고침. 서버 재시작 시 소멸(허용).
- `Session = {history, member_id('m-001' 고정), cart_items, orders, lock, last_seen}`.
- **히스토리 캡**: 30개 메시지 초과 시 오래된 것부터 제거(반드시 일반 user 텍스트 턴으로 시작하도록 정리 — tool_result로
  시작하면 400). 12개를 넘으면 최근 6개를 제외한 assistant 턴의 A2UI JSON 펜스를 한 줄 마커로 축약.
- 히스토리를 실제로 편집한 턴에만 thinking 블록을 제거한다 — Opus 5.5부터 thinking 블록이 생성 당시의
  프리픽스에 묶이므로(preserved thinking) 편집 후 그대로 보내면 400.
- TTL: 마지막 접근 후 1시간.

### 8-3. `GET /api/member` — 화면 진입 시 헤더 포인트 초기화 (members 행 + `expire_in_days`).

### 8-4. `GET /api/health`

```json
{"llm_provider": "anthropic", "model": "claude-opus-5-5", "effort": "medium",
 "db": "ok", "products": 317, "anthropic_api_key": "set"}
```
bedrock 모드에서는 `aws_creds`(STS caller identity) 필드가 대신 들어간다.

### FE (`remote_agent.dart`)

- `ScriptedShoppingAgent`와 동일한 시그니처 — `chat_session.dart`의 인스턴스 생성만 AgentFactory로 교체.
- **Flutter 웹 스트리밍 주의**: `package:http`의 기본 웹 클라이언트(XHR)는 응답 바디를 스트리밍하지 못한다.
  `fetch_client`(browser fetch + ReadableStream)로 POST+SSE를 읽는다.
- 잔여 포인트 표시는 `done` 이벤트 값으로 갱신.

## 9. 환경 설정

`shop_backend/.env` (`.env.example` 제공, 실파일은 .gitignore) + 선택 오버레이 `shop_backend/.env.local`
(`.env.bedrock.example` 제공, `.env` 위에 override, `.env.*` 규칙으로 git 제외 — 회사 고유 값 전용):

```
DATABASE_URL=postgresql://postgres:postgres@localhost:5432/shop_db

LLM_PROVIDER=anthropic        # anthropic | bedrock
ANTHROPIC_API_KEY=sk-ant-...
CLAUDE_MODEL_ID=              # 비우면 공급자별 기본값
LLM_EFFORT=medium             # low/medium/high

# BEDROCK_REGION=us-east-1    # bedrock일 때 (상세: .env.bedrock.example)
# AWS_PROFILE=default
# BEDROCK_BASE_URL=           # 사내 게이트웨이를 거칠 때만 (.env.local)

DEMO_LANGUAGE=en              # en | ko — 모델 응답 언어·서버 안내 문구 기본값 (FE ⚙ 메뉴의 lang이 우선)
PORT=8010
DATA_GO_KR_API_KEY=           # (선택) 참가격 실데이터 수집
```

설치·실행:
```
pip install -r requirements.txt
python scripts/init_db.py                 # DB 생성 + 스키마 + 고정 시드
python scripts/fetch_seed_data.py         # (선택) 실데이터 수백 종 추가
run_server.bat  |  sh run_server.sh       # uvicorn app.main:app --port 8010
```

## 10. 구현 순서 (완료)

| 단계 | 내용 | 완료 기준 |
|---|---|---|
| 1 | DB: `init_db.py` + schema + seed + `fetch_seed_data.py` | 상품 수백 종, 도구용 쿼리 수동 검증 |
| 2 | 도구 (`tools.py`, `orders.py`, `db.py`) + 단위 테스트 | `pytest tests/test_tools.py` 통과 (DB 실연동) |
| 3 | 에이전트 루프 + 시스템 프롬프트 + SSE 엔드포인트 | `curl -N`으로 캠핑 질의 → 실제 tool trace + 유효 A2UI JSON |
| 4 | FE `remote_agent.dart` + fetch_client | 브라우저 E2E: 질의 → 카드 → 담기 → 접수 → 확정 |
| 5 | 동적성 검증 시나리오 실행 + 결과 기록 | §11의 3개 시나리오 통과 → [verification/](verification/README.md) |

## 11. 동적성 검증 시나리오 (판정 기준)

1. **같은 의도, 다른 조건**: "저염 반찬 추천" vs "1만원 이하 부모님 선물" → 서로 다른 도구 인자와 다른 컴포넌트 구성이 나오는가
2. **DB 변경 반영**: `UPDATE products SET price=... WHERE id='sleeping_bag_a'` 후 동일 질의 → UI 숫자가 따라 바뀌는가
3. **스크립트에 없는 질의**: "5만원으로 캠핑 준비물 다 골라줘" → 사전 정의 없는 질의에서 즉석 검색·조합·UI 생성하는가

SSE 원문 로그를 `docs/verification/`에 보존. 결과: 3개 모두 통과.

### 턴 로그 (`turn_log.py`)

모든 턴을 `shop_backend/logs/turns/YYYYMMDD.jsonl`에 1줄씩 기록:

```json
{"ts": "...", "session_id": "...", "user_input": "...",
 "tool_calls": [{"name": "search_products", "input": {...}, "is_error": false, "ms": 42, "result_size": 1830}],
 "assistant_text_len": 312, "stop_reason": "end_turn", "error": null,
 "usage": {"input_tokens": 0, "output_tokens": 0, "cache_read_input_tokens": 0}, "latency_ms": 0}
```

## 12. 리스크와 대응

| 리스크 | 영향 | 대응 |
|---|---|---|
| LLM이 부정확한 A2UI JSON 생성 (스키마 위반, root id 누락) | Surface 렌더 실패 | 시스템 프롬프트에 스키마+few-shot. FE 파이프라인이 에러 표시. 실측에서는 위반 없음 |
| 인증 만료/누락 | LLM 호출 실패 | `/api/health`에서 점검, 오류 시 SSE error로 안내 문구 |
| adaptive thinking + effort=medium 응답 지연 | 데모 체감 저하 | 텍스트 즉시 스트리밍으로 완화. 과도하면 `LLM_EFFORT=low` |
| 히스토리 축약 마커 모방 | 모델이 JSON 대신 마커 출력 | 최근 6개 턴 원문 유지 + 프롬프트에 모방 금지 명시 |
| 스트림 도중 일시 오류 | 턴 중단 | 텍스트 출력 전이면 2회 재시도, 이후면 error 이벤트 |

## 13. 결정 사항 요약

| 항목 | 결정 |
|---|---|
| LLM 연결 | Anthropic API 직결 기본, Bedrock 선택 — `llm.py` 한 곳에서 분기 |
| 시드 규모 | 고정 시드 + 실데이터 수집으로 수백 종 (리얼리즘) |
| UI 액션 처리 | 하드코딩 라우팅 없이 LLM 판단에 위임 |
| effort | 기본 `medium` (품질 우선), `.env`로 변경 |
| mock 유지 | `--dart-define=AGENT_MODE=remote(기본)|scripted`, 위젯 테스트는 scripted로 존속 |
| 세션 저장 | 인메모리 — 재시작 시 초기화 허용, 증적은 턴 JSONL 로그로 보존 |
| tool trace | 텍스트 청크에 삽입 — mock과 동일한 `▸ ...` 라인, FE 무변경 |
| HITL | 돈이 움직이는 DB 쓰기는 `confirm_payment` 한 곳, 사람이 버튼 3번 — [hitl.md](hitl.md) |
