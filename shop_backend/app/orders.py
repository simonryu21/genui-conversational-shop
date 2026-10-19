"""세션 기반 장바구니·주문 (2026-08-27 시나리오 변경 — 결제 확정 전에는 DB 불변).

3단계 구매 흐름:
1. create_cart_draft — 세션 장바구니 (DB는 상품 검증 조회만)
2. submit_order    — 주문 **접수** (세션 메모리, 포인트는 예약만 — 실제 차감 없음)
3. confirm_payment — 결제 **확정** (이때만 DB에 주문·포인트 차감·원장·구매이력 기록)

FE reload → 새 session_id → 미확정 상태 소멸 → 헤더는 실제 DB 포인트로 복귀.
"""
import itertools
import re

from . import db
from .db import ToolError
from .sessions import Session

PAYMENT_METHODS = ("신용카드", "간편결제")


def _seed_order_counter():
    """주문번호 시작값 — DB 기존 주문과 충돌하지 않게 최대값+1부터."""
    start = 1040
    try:
        with db.pool.connection() as conn:
            row = conn.execute("SELECT max(id) AS m FROM orders").fetchone()
        if row["m"]:
            digits = re.sub(r"\D", "", row["m"])  # 'WF-2026-1043' → '20261043'
            start = max(start, int(digits[4:]))
    except Exception:
        pass
    return itertools.count(start + 1)


_order_seq = _seed_order_counter()


def _available_points(session: Session) -> tuple[int, int]:
    """(실제 DB 포인트, 미확정 예약분 차감 후 가용 포인트)."""
    actual = db.current_points(session.member_id)
    return actual, max(0, actual - session.pending_points())


def _cart_view(session: Session, note: str | None = None) -> dict:
    """세션 단일 장바구니의 현재 상태 (CartSummary 작성용)."""
    total = sum(i["price"] for i in session.cart_items)
    actual, available = _available_points(session)
    shortfall = max(0, total - available)
    view = {
        "items": session.cart_items,           # 각 항목에 product_id 포함 (삭제 버튼용)
        "item_count": len(session.cart_items),
        "total": total,
        "points_actual": actual,               # 실제 DB 포인트 (헤더 표시값)
        "points_available": available,          # 미확정 예약분 차감 후 가용
        "balance_after": max(0, available - total),
        "shortfall": shortfall,
        "extra_payment_required": shortfall > 0,
    }
    if note:
        view["note"] = note
    return view


def add_to_cart(session: Session, product_ids: list[str]) -> dict:
    """세션 단일 장바구니에 상품 추가 — 기존 담은 상품과 합쳐진다."""
    if not product_ids:
        raise ToolError("product_ids가 비어 있음")
    prods = db.products_by_ids(product_ids)  # 존재·재고 검증 (조회만)
    existing = {i["product_id"] for i in session.cart_items}
    skipped = [p["name"] for p in prods if p["id"] in existing]
    for p in prods:
        if p["id"] not in existing:
            session.cart_items.append(
                {"product_id": p["id"], "name": p["name"], "price": p["price"]}
            )
    note = f"이미 담겨 있어 건너뜀: {skipped}" if skipped else None
    return _cart_view(session, note)


def remove_from_cart(session: Session, product_ids: list[str]) -> dict:
    """장바구니에서 상품 제거."""
    if not product_ids:
        raise ToolError("product_ids가 비어 있음")
    before = {i["product_id"] for i in session.cart_items}
    missing = [p for p in product_ids if p not in before]
    if missing:
        raise ToolError(f"장바구니에 없는 상품: {missing}")
    session.cart_items = [i for i in session.cart_items if i["product_id"] not in product_ids]
    return _cart_view(session)


def submit_order(session: Session, payment_method: str | None = None) -> dict:
    """주문 접수 — 세션 장바구니 전체를 접수 (세션에만 기록, 차감은 confirm_payment에서)."""
    if not session.cart_items:
        raise ToolError("장바구니가 비어 있습니다. 먼저 상품을 담아주세요.")
    items = list(session.cart_items)
    total = sum(i["price"] for i in items)
    _, available = _available_points(session)
    points_used = min(available, total)
    extra = total - points_used
    if extra > 0:
        if not payment_method:
            raise ToolError(
                f"포인트 부족분 {extra:,}원의 결제수단이 필요합니다. "
                f"사용자에게 확인 후 payment_method에 {' 또는 '.join(PAYMENT_METHODS)}를 "
                "지정해 다시 호출하세요 (데모라 실결제는 발생하지 않음)."
            )
        if payment_method not in PAYMENT_METHODS:
            raise ToolError(f"지원하지 않는 결제수단: {payment_method} (가능: {PAYMENT_METHODS})")
    else:
        payment_method = None

    order_id = f"WF-2026-{next(_order_seq)}"
    order = {
        "order_id": order_id,
        "items": items,
        "item_count": len(items),
        "total": total,
        "points_used": points_used,
        "extra_amount": extra,
        "payment_method": payment_method,
        "status": "결제 대기",
    }
    session.orders[order_id] = order
    session.cart_items = []  # 접수된 장바구니는 비움

    pay_desc = f"포인트 {points_used:,}P" + (
        f" + {payment_method} {extra:,}원" if extra > 0 else ""
    )
    return {
        **order,
        "status": f"결제 대기 — {pay_desc} (확정 전: 포인트 미차감, 실결제 없음)",
        "points_available_after_confirm": available - points_used,
        "note": "결제 확정 시에만 실제 포인트가 차감됩니다. 확정 전 이탈(reload) 시 접수는 사라집니다.",
    }


def confirm_payment(session: Session, order_id: str) -> dict:
    """결제 확정 (데모 가상 결제) — 이때만 DB에 기록·차감."""
    order = session.orders.get(order_id)
    if order is None:
        raise ToolError(f"접수된 주문 없음: {order_id} (reload 시 미확정 주문은 사라집니다)")
    if order["status"] != "결제 대기":
        raise ToolError(f"이미 처리된 주문: {order_id} (status={order['status']})")

    balance_after = db.confirm_order(session.member_id, order)
    order["status"] = "결제 완료"

    pay_desc = f"포인트 {order['points_used']:,}P" + (
        f" + {order['payment_method']} {order['extra_amount']:,}원"
        if order["extra_amount"] > 0 else ""
    )
    return {
        "order_id": order_id,
        "item_count": order["item_count"],
        "total": order["total"],
        "points_used": order["points_used"],
        "extra_amount": order["extra_amount"],
        "payment_method": order["payment_method"],
        "balance_after": balance_after,          # 실제 DB 잔여 (헤더에 반영됨)
        "status": f"결제 완료 — {pay_desc} (데모: 실결제 없음)",
    }
