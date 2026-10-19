"""도구 7종 단위 테스트 — shop_db 실연동 (설계 §10 2단계 + 2026-08-27 시나리오 변경).

구매 흐름: 담기/접수는 세션 메모리(DB 불변), confirm_payment만 DB 기록.
쓰기 테스트(confirm)는 실행 후 스스로 원상복구한다 (데모 DB 보호).
실행:  pytest tests/test_tools.py -v
"""
import json

import pytest

from app import db
from app.sessions import Session
from app.tools import execute_tool

M = "m-001"


@pytest.fixture
def session():
    return Session("test-session")


def call(name, args, session=None):
    result, is_error = execute_tool(name, args, session or Session("test-adhoc"))
    return (json.loads(result) if not is_error else result), is_error


# ---------------------------------------------------------------------------
# 조회 도구
# ---------------------------------------------------------------------------

def test_get_member():
    out, err = call("get_member", {"member_id": M})
    assert not err
    assert out["name"] == "김민수"
    assert isinstance(out["points"], int)
    assert out["points_available"] == out["points"]  # 새 세션 — 예약분 없음
    assert "expire_in_days" in out


def test_get_member_missing():
    _, err = call("get_member", {"member_id": "m-999"})
    assert err


def test_get_purchase_history_with_category():
    out, err = call("get_purchase_history", {"member_id": M, "category": "캠핑"})
    assert not err
    assert any(r["product_id"] == "led_lantern" for r in out)


def test_search_by_tags():
    out, err = call("search_products", {
        "query": None, "category": None, "tags": ["저염", "반찬"],
        "max_price": None, "min_price": None,
        "in_stock_only": True, "sort": "price_asc", "limit": 10,
    })
    assert not err
    assert out["returned"] >= 3
    prices = [p["price"] for p in out["products"]]
    assert prices == sorted(prices)


def test_search_query_and_price():
    out, err = call("search_products", {
        "query": "참치", "category": "식품", "tags": None,
        "max_price": 10000, "min_price": None,
        "in_stock_only": True, "sort": "price_asc", "limit": 10,
    })
    assert not err
    assert all(p["price"] <= 10000 for p in out["products"])
    assert out["total_matched"] >= 1


def test_search_excludes_out_of_stock():
    out, err = call("search_products", {
        "query": "화로대", "category": None, "tags": None,
        "max_price": None, "min_price": None,
        "in_stock_only": True, "sort": "relevance", "limit": 10,
    })
    assert not err
    assert out["returned"] == 0  # fire_pit은 재고 0으로 시드됨


def test_get_product_specs():
    out, err = call("get_product_specs", {"product_ids": ["sleeping_bag_a", "sleeping_bag_b"]})
    assert not err
    assert {r["product_id"] for r in out} == {"sleeping_bag_a", "sleeping_bag_b"}
    assert out[0]["specs"]  # 비교표 소재 존재


def test_get_product_specs_missing_id():
    _, err = call("get_product_specs", {"product_ids": ["no_such_product"]})
    assert err


# ---------------------------------------------------------------------------
# 쓰기 도구 — 실행 후 원상복구
# ---------------------------------------------------------------------------

@pytest.fixture
def restore_db():
    before = db.current_points(M)
    created = {"orders": []}
    yield created
    with db.pool.connection() as conn:
        for oid in created["orders"]:
            conn.execute("DELETE FROM point_ledger WHERE reason LIKE %s", (f"%{oid}%",))
            conn.execute(
                "DELETE FROM purchase_history WHERE purchased_at = CURRENT_DATE AND member_id = %s", (M,))
            conn.execute("DELETE FROM orders WHERE id = %s", (oid,))
        conn.execute("UPDATE members SET points = %s WHERE id = %s", (before, M))


def _set_points(v: int) -> None:
    with db.pool.connection() as conn:
        conn.execute("UPDATE members SET points = %s WHERE id = %s", (v, M))


def test_cart_merges_and_submit_does_not_touch_db(session, restore_db):
    """담기는 단일 장바구니에 누적, 접수는 세션 메모리만 — DB 불변 (reload 시 원복)."""
    _set_points(180000)
    cart, err = call("add_to_cart", {"product_ids": ["down_blanket"]}, session)
    assert not err and cart["item_count"] == 1

    # 두 번째 담기 → 기존 항목과 병합된 전체 장바구니 반환
    cart, err = call("add_to_cart", {"product_ids": ["thermos_1l"]}, session)
    assert not err
    assert cart["item_count"] == 2
    assert cart["total"] == 27000 + 24000
    assert {i["product_id"] for i in cart["items"]} == {"down_blanket", "thermos_1l"}
    assert all("product_id" in i for i in cart["items"])  # 삭제 버튼용 id 포함

    # 중복 담기는 건너뜀
    cart, err = call("add_to_cart", {"product_ids": ["down_blanket"]}, session)
    assert not err and cart["item_count"] == 2 and "건너뜀" in cart.get("note", "")

    order, err = call("submit_order", {"payment_method": None}, session)
    assert not err
    assert order["order_id"].startswith("WF-2026-")
    assert order["points_used"] == 51000
    assert "미차감" in order["status"]

    # 핵심: DB는 아무것도 변하지 않았고, 접수 후 장바구니는 비었다
    assert db.current_points(M) == 180000
    with db.pool.connection() as conn:
        row = conn.execute("SELECT count(*) AS c FROM orders WHERE id = %s",
                           (order["order_id"],)).fetchone()
    assert row["c"] == 0
    assert session.cart_items == []

    # 빈 장바구니 재접수는 거부
    _, err = call("submit_order", {"payment_method": None}, session)
    assert err


def test_remove_from_cart(session):
    _set_points(180000)
    call("add_to_cart", {"product_ids": ["down_blanket", "thermos_1l"]}, session)
    cart, err = call("remove_from_cart", {"product_ids": ["down_blanket"]}, session)
    assert not err
    assert cart["item_count"] == 1
    assert cart["items"][0]["product_id"] == "thermos_1l"
    assert cart["total"] == 24000

    result, err = call("remove_from_cart", {"product_ids": ["no_such"]}, session)
    assert err and "장바구니에 없는" in result


def test_confirm_payment_writes_db(session, restore_db):
    """결제 확정 시에만 DB에 주문·차감·원장·구매이력 기록."""
    _set_points(180000)
    def history_count():
        with db.pool.connection() as conn:
            return conn.execute(
                "SELECT count(*) AS c FROM purchase_history"
                " WHERE member_id = %s AND product_id = 'down_blanket'"
                " AND purchased_at = CURRENT_DATE", (M,)).fetchone()["c"]

    h_before = history_count()
    call("add_to_cart", {"product_ids": ["down_blanket"]}, session)
    order, _ = call("submit_order", {"payment_method": None}, session)
    restore_db["orders"].append(order["order_id"])

    confirmed, err = call("confirm_payment", {"order_id": order["order_id"]}, session)
    assert not err
    assert confirmed["balance_after"] == 180000 - 27000
    assert db.current_points(M) == 153000  # 실제 차감

    with db.pool.connection() as conn:
        o = conn.execute("SELECT status FROM orders WHERE id = %s",
                         (order["order_id"],)).fetchone()
    assert o is not None and "결제 완료" in o["status"]
    assert history_count() == h_before + 1  # 구매이력 추가 (이후 추천 근거로 활용)

    # 같은 주문 재확정은 거부
    _, err = call("confirm_payment", {"order_id": order["order_id"]}, session)
    assert err


def test_mixed_payment_uses_available_points(session, restore_db):
    """포인트 초과 구매 — 가용 포인트 + 결제수단, 접수 단계에선 여전히 DB 불변."""
    _set_points(50000)
    cart, err = call("add_to_cart", {"product_ids": ["sleeping_bag_a"]}, session)
    assert not err
    assert cart["shortfall"] == 39000
    assert cart["balance_after"] == 0

    result, err = call("submit_order", {"payment_method": None}, session)
    assert err and "결제수단" in result

    order, err = call("submit_order", {"payment_method": "간편결제"}, session)
    assert not err
    assert order["points_used"] == 50000 and order["extra_amount"] == 39000
    assert db.current_points(M) == 50000  # 접수만으로는 미차감

    restore_db["orders"].append(order["order_id"])
    confirmed, err = call("confirm_payment", {"order_id": order["order_id"]}, session)
    assert not err
    assert confirmed["balance_after"] == 0
    assert "간편결제 39,000원" in confirmed["status"]


def test_pending_reservation_reduces_available(session, restore_db):
    """미확정 주문의 예약분이 get_member.points_available과 다음 장바구니 계산에 반영."""
    _set_points(180000)
    call("add_to_cart", {"product_ids": ["air_fryer_5l"]}, session)  # 89,000
    call("submit_order", {"payment_method": None}, session)

    m, err = call("get_member", {"member_id": M}, session)
    assert not err
    assert m["points"] == 180000            # 실제(헤더)는 불변
    assert m["pending_reserved"] == 89000
    assert m["points_available"] == 91000   # 가용은 예약분 차감

    cart2, _ = call("add_to_cart", {"product_ids": ["stick_vacuum"]}, session)  # 179,000
    assert cart2["points_available"] == 91000
    assert cart2["shortfall"] == 179000 - 91000


def test_cart_rejects_out_of_stock(session):
    result, err = call("add_to_cart", {"product_ids": ["fire_pit"]}, session)
    assert err
    assert "재고" in result


def test_order_rejects_unknown_payment_method(session, restore_db):
    _set_points(1000)
    call("add_to_cart", {"product_ids": ["camp_pillow_air"]}, session)
    result, err = call("submit_order", {"payment_method": "현금"}, session)
    assert err
    assert "지원하지 않는" in result
