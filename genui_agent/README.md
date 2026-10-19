# genui_agent — 대화형 쇼핑 GenUI 클라이언트 (Flutter Web)

[flutter/genui](https://github.com/flutter/genui) SDK(`genui` 0.10.x, A2UI v0.9 프로토콜)로 만든
**사용자 질의에 따라 UI 형태가 달라지는** 대화형 쇼핑 에이전트의 클라이언트.
기본 모드에서는 `shop_backend/`(FastAPI + Claude)에 SSE로 연결하고,
`scripted` 모드에서는 규칙 기반 mock 에이전트로 백엔드 없이 오프라인 시연이 가능하다.

## 질의 → UI 형태 매핑 (데모 시나리오)

| 사용자 입력 | 에이전트가 생성하는 UI |
|---|---|
| "남은 포인트로 겨울 캠핑 용품 추천해줘" | **ProductGrid** — 추천 카드 3종 + 합계 + 세트 담기 버튼 |
| "침낭 두 개 비교해줘" | **ComparisonTable** — 스펙 비교표 + 열별 담기 버튼 |
| "참치캔 추천해줘" | **인터뷰형 폼** — ChoicePicker×2 + 제출 버튼 (표준 카탈로그만 사용) |
| "잔여 포인트 얼마야?" | UI 없음 — **텍스트만** (에이전트가 UI 불필요를 판단) |
| 카드에서 "담기" 클릭 | **CartSummary** — 장바구니 + HITL 안내 + 결제 진행 버튼 |
| "결제 단계로 진행" 클릭 | **OrderConfirmation** — 주문 접수(결제 대기) 카드 + 결제 확정 버튼 |

UI 안의 버튼·선택은 `UserActionEvent`로 다시 에이전트에게 전달되어 다음 턴을 만든다
(예: 참치캔 폼에서 브랜드/타입 선택 → 제출 → 조건에 맞는 추천 카드).

## 아키텍처

```
사용자 입력/UI 액션
   │
   ▼
ShoppingAgent (lib/agent/shopping_agent.dart)      ← 인터페이스. AgentFactory가 모드별 구현 선택
   ├─ RemoteShoppingAgent (lib/agent/remote_agent.dart)   POST /api/chat → SSE 수신 (기본)
   └─ ScriptedShoppingAgent (lib/scripted_agent.dart)     규칙 기반 mock (AGENT_MODE=scripted)
   │  텍스트 + ```json``` A2UI v0.9 메시지를 청크 단위로 스트리밍
   ▼
A2uiTransportAdapter.addChunk()                    ← genui SDK: 스트림 버퍼링·JSON 추출
   │  incomingText → 채팅 말풍선 / incomingMessages → A2UI 메시지
   ▼
SurfaceController (catalogs: [shopCatalog])        ← genui SDK: 스키마 검증·서피스 상태
   │  surfaceUpdates → 타임라인에 서피스 추가
   ▼
Surface(surfaceContext: contextFor(surfaceId))     ← genui SDK: 위젯 렌더링
   │  버튼 클릭 → onSubmit(ChatMessage + UiInteractionPart)
   └──────────────→ 다시 에이전트로 (피드백 루프)
```

- **lib/shop_catalog.dart** — 도메인 커스텀 `CatalogItem` 4종(ProductGrid, ComparisonTable,
  CartSummary, OrderConfirmation)을 정의하고 기본 카탈로그(Text/Column/Button/ChoicePicker 등)와 합쳐
  `catalogId: com.example.welfare-shop` 카탈로그를 구성. 두 모드 모두 이 카탈로그를 그대로 쓴다.
- **lib/agent/remote_agent.dart** — `ChatMessage`를 백엔드 요청 JSON으로 직렬화하고
  SSE `chunk` 이벤트를 `emitChunk`로 중계, `done` 이벤트로 헤더 포인트 갱신.
  웹에서는 `fetch_client`로 POST 응답을 스트리밍한다 (`package:http` 기본 XHR은 스트리밍 불가).
- **lib/scripted_agent.dart** — 데모 재현성을 위한 규칙 기반 mock. **출력 형식은 실제 LLM과 동일**
  (텍스트+JSON 블록 스트리밍)이라 파싱·검증·렌더링·액션 루프는 전부 genui SDK 경로를 그대로 통과한다.
- **lib/chat_session.dart** — 위 파이프라인 배선 + 채팅 타임라인 상태 + 데모 언어 상태(`setLanguage`).
- **lib/l10n.dart** — 앱 크롬 문자열(헤더·추천 칩·힌트·액션 라벨·오류) ko/en. 모델 응답 언어는 BE가 요청의 `lang`으로
  시스템 프롬프트를 바꿔 결정한다. scripted mock의 응답 본문은 한국어뿐(영어 칩은 같은 시나리오로 라우팅).

## 실행

```sh
flutter pub get

# 1) 백엔드 연동 (기본) — shop_backend가 http://localhost:8010 에서 실행 중이어야 함
flutter run -d chrome
flutter run -d chrome --dart-define=BE_URL=http://other-host:8010

# 2) 오프라인 mock
flutter run -d chrome --dart-define=AGENT_MODE=scripted

# 3) 시작 언어 (기본 en) — 실행 중에는 헤더 ⚙ 메뉴에서 한국어/English 전환
flutter run -d chrome --dart-define=DEMO_LANG=ko

# 테스트 (VM에서는 자동으로 scripted 모드)
flutter test
```

정적 빌드: `flutter build web` 후 `build/web`을 임의의 정적 서버로 서빙
(`--dart-define`은 빌드 시점에 지정).
