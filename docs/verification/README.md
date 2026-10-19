# GenUI 동적성 검증 결과 (설계 §11)

실행일: 2026-08-27 / 모델: Claude Opus 4.8 (AWS Bedrock 경유, effort=medium)
방법: `POST /api/chat` SSE 원문 보존 (`*.sse.txt`) — UI 코드(Flutter)는 무변경 상태에서 실행.
턴별 도구 호출·usage는 `shop_backend/logs/turns/*.jsonl` 참조.

## 판정: 3개 시나리오 모두 통과 — GenUI는 질의·LLM 답변·DB 상태에 따라 동적으로 UI를 생성한다

### 1. 같은 의도, 다른 조건 → 다른 도구 인자 + 다른 UI 구성 ✅

| 질의 | LLM이 선택한 검색 조건 | 생성된 UI |
|---|---|---|
| "저염 반찬 추천해줘" | `tags=['저염','반찬'], category=식품, sort=repurchase` | ProductGrid "저염 반찬 추천 3종" (장조림 12,900 · 멸치볶음 8,900 · 백김치 19,000) |
| "1만원 이하로 부모님 선물 추천해줘" | `max_price=10000, category=선물` → 결과 부족하자 **스스로 3회 재검색** | ProductGrid "1만원 이하 부모님 선물" (핸드크림 9,900 · 양말세트 8,900) |

### 2. DB 변경 반영 — 스크립트가 아니라는 결정적 증거 ✅

`UPDATE products SET price=129000 WHERE id='sleeping_bag_a'` (원래 89,000) 후 동일 질의
→ 생성된 카드에 **129,000P**로 표시. LLM은 합계가 잔여 포인트를 "살짝 넘"는다고 텍스트로 고지.
(검증 후 89,000으로 복구)

### 3. 사전 정의 없는 질의 ✅

"5만원으로 캠핑 준비물 최대한 알뜰하게 골라줘" (mock 스크립트에 없던 질의)
→ `max_price=50000, sort=price_asc`로 검색 후 **합계 49,700P** 3종 세트 구성 (블랭킷+핫팩+에어베개).

## 추가 관찰 (스모크 테스트에서)

- **자율 복구**: 검색 0건 시 "조건을 넓혀 다시 찾아볼게요" 후 재검색 (규칙 기반으로는 불가능한 거동).
- **전체 구매 루프**: addToCart 액션 → `create_cart_draft` → CartSummary / checkout → `submit_order`
  (세션 히스토리에서 cart_id 기억) → OrderConfirmation + 실제 포인트 차감·원장 기록.
- **UI 억제 판단**: "잔여 포인트 얼마야?"에는 UI 없이 텍스트만 (소멸 D-4 계산 정확).
- 프롬프트 캐시 적중: 매 턴 `cache_read_input_tokens=4068`. 턴 지연 6~26초.
