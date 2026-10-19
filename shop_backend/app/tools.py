"""LLM 도구 6종 — strict JSON Schema 정의 + 실행 디스패치 (설계 §5).

데모의 가짜 trace(get_member_points, search_products, get_specs,
create_cart_draft+check_balance, submit_order+ledger.append)를 실제 함수로 정규화.
"""
import json
from typing import Any

from . import db, orders
from .sessions import Session

TOOL_SCHEMAS: list[dict] = [
    {
        "name": "get_member",
        "description": (
            "회원의 잔여 복지포인트, 등급, 소멸 예정 포인트(소멸일·D-day)를 조회한다. "
            "points는 실제 잔여(확정된 결제만 반영, 헤더 표시값), points_available은 "
            "이 세션에서 접수 후 미확정인 주문의 예약분까지 뺀 가용 포인트다."
        ),
        "input_schema": {
            "type": "object",
            "properties": {"member_id": {"type": "string"}},
            "required": ["member_id"],
            "additionalProperties": False,
        },
    },
    {
        "name": "get_purchase_history",
        "description": "회원의 과거 구매 이력을 최신순으로 조회한다. 추천 근거(재구매·취향 파악)에 사용.",
        "input_schema": {
            "type": "object",
            "properties": {
                "member_id": {"type": "string"},
                "category": {
                    "type": ["string", "null"],
                    "description": "카테고리 필터 (식품/캠핑/가전/리빙/선물/생필품). 전체는 null",
                },
            },
            "required": ["member_id", "category"],
            "additionalProperties": False,
        },
    },
    {
        "name": "search_products",
        "description": (
            "상품을 검색한다. 키워드(이름·태그), 카테고리, 태그 완전일치, 가격 범위, 재고, "
            "정렬을 조합할 수 있다. total_matched로 전체 매칭 수를 알려주므로 후보가 많으면 "
            "조건을 좁히는 질문(인터뷰 UI)을 고려하라."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": ["string", "null"], "description": "키워드 (공백 구분 AND)"},
                "category": {
                    "type": ["string", "null"],
                    "enum": ["식품", "캠핑", "가전", "리빙", "선물", "생필품", None],
                },
                "tags": {
                    "type": ["array", "null"],
                    "items": {"type": "string"},
                    "description": "모두 포함해야 하는 태그 (예: ['저염','반찬'])",
                },
                "max_price": {"type": ["integer", "null"]},
                "min_price": {"type": ["integer", "null"]},
                "in_stock_only": {"type": "boolean"},
                "sort": {
                    "type": "string",
                    "enum": ["relevance", "price_asc", "price_desc", "repurchase"],
                },
                "limit": {"type": "integer", "minimum": 1, "maximum": 30},
            },
            "required": ["query", "category", "tags", "max_price", "min_price",
                          "in_stock_only", "sort", "limit"],
            "additionalProperties": False,
        },
    },
    {
        "name": "get_product_specs",
        "description": "상품들의 상세 스펙(specs)을 조회한다. 비교표(ComparisonTable) 작성에 사용.",
        "input_schema": {
            "type": "object",
            "properties": {
                "product_ids": {"type": "array", "items": {"type": "string"}, "minItems": 1},
            },
            "required": ["product_ids"],
            "additionalProperties": False,
        },
    },
    {
        "name": "add_to_cart",
        "description": (
            "세션 장바구니에 상품을 추가한다 — **기존에 담긴 상품과 합쳐진 전체 장바구니**가 반환되므로 "
            "CartSummary에는 반환된 items 전체를 표시하라 (세션 메모리 — 확정 전 기록·차감 없음). "
            "사용자가 '담기'(addToCart) 액션을 보냈을 때 호출하라."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "product_ids": {"type": "array", "items": {"type": "string"}, "minItems": 1},
            },
            "required": ["product_ids"],
            "additionalProperties": False,
        },
    },
    {
        "name": "remove_from_cart",
        "description": (
            "세션 장바구니에서 상품을 제거하고 갱신된 전체 장바구니를 반환한다. "
            "사용자가 항목 삭제(removeFromCart) 액션을 보냈을 때 호출하라."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "product_ids": {"type": "array", "items": {"type": "string"}, "minItems": 1},
            },
            "required": ["product_ids"],
            "additionalProperties": False,
        },
    },
    {
        "name": "submit_order",
        "description": (
            "세션 장바구니 **전체**를 주문으로 **접수**한다 (세션 메모리 가예약 — 실제 포인트 차감 없음, "
            "접수 후 장바구니는 비워짐). 포인트는 가용분까지 예약되고, 부족분은 payment_method"
            "(신용카드/간편결제)로 지정한다. 부족분이 있는데 payment_method가 없으면 오류가 나므로 "
            "먼저 사용자에게 결제수단을 확인하라. 실제 차감·기록은 confirm_payment에서만 일어난다. "
            "사용자가 '결제 단계로 진행'(checkout) 액션을 보냈을 때 호출하라."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "payment_method": {
                    "type": ["string", "null"],
                    "enum": ["신용카드", "간편결제", None],
                    "description": "포인트 부족분 결제수단. 포인트로 전액 결제 가능하면 null",
                },
            },
            "required": ["payment_method"],
            "additionalProperties": False,
        },
    },
    {
        "name": "confirm_payment",
        "description": (
            "접수된 주문의 결제를 **확정**한다 (데모 가상 결제 — 실결제 없음). "
            "이때만 실제로 포인트가 차감되고 주문·원장·구매이력이 기록되며, 헤더의 잔여 포인트가 바뀐다. "
            "사용자가 '결제 확정'(confirmPayment) 액션을 보냈을 때 호출하라."
        ),
        "input_schema": {
            "type": "object",
            "properties": {"order_id": {"type": "string"}},
            "required": ["order_id"],
            "additionalProperties": False,
        },
    },
]

def _get_member(session: Session, a: dict) -> dict:
    m = db.get_member(a["member_id"])
    pending = session.pending_points()
    m["pending_reserved"] = pending          # 이 세션에서 접수 후 미확정 예약분
    m["points_available"] = max(0, m["points"] - pending)
    return m


_IMPL = {
    "get_member": _get_member,
    "get_purchase_history": lambda s, a: db.get_purchase_history(a["member_id"], a.get("category")),
    "search_products": lambda s, a: db.search_products(
        query=a.get("query"), category=a.get("category"), tags=a.get("tags"),
        max_price=a.get("max_price"), min_price=a.get("min_price"),
        in_stock_only=a.get("in_stock_only", True),
        sort=a.get("sort", "relevance"), limit=a.get("limit", 10),
    ),
    "get_product_specs": lambda s, a: db.get_product_specs(a["product_ids"]),
    "add_to_cart": lambda s, a: orders.add_to_cart(s, a["product_ids"]),
    "remove_from_cart": lambda s, a: orders.remove_from_cart(s, a["product_ids"]),
    "submit_order": lambda s, a: orders.submit_order(s, a.get("payment_method")),
    "confirm_payment": lambda s, a: orders.confirm_payment(s, a["order_id"]),
}


def execute_tool(name: str, args: dict[str, Any], session: Session) -> tuple[str, bool]:
    """(result_json, is_error) 반환. 예외는 LLM이 복구를 시도하도록 문자열로 전달."""
    impl = _IMPL.get(name)
    if impl is None:
        return f"알 수 없는 도구: {name}", True
    try:
        result = impl(session, args)
        return json.dumps(result, ensure_ascii=False, default=str), False
    except db.ToolError as e:
        return str(e), True
    except Exception as e:  # DB 장애 등 — LLM에게 사실대로 알림
        return f"도구 실행 오류({type(e).__name__}): {e}", True


def summarize_input(name: str, args: dict[str, Any]) -> str:
    """화면 trace 라인용 — 핵심 인자만 간결하게."""
    parts = [f"{k}={v}" for k, v in args.items() if v not in (None, [], "")]
    return f"{name}({', '.join(parts)})"
