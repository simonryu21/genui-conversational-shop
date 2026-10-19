"""psycopg 커넥션 풀 + 도구별 쿼리 함수 (설계 §5).

모든 함수는 dict/list를 반환한다 — tools.execute_tool이 JSON으로 직렬화.
비즈니스 오류(잔액 부족 등)는 ToolError로 던진다 → tool_result is_error=True.
"""
from datetime import date

from psycopg.rows import dict_row
from psycopg.types.json import Json
from psycopg_pool import ConnectionPool

from .config import settings

pool = ConnectionPool(settings.database_url, min_size=1, max_size=4, open=False,
                      kwargs={"row_factory": dict_row})
pool.open()  # import 시점 오픈 — 앱/테스트/스크립트 어디서든 바로 사용 가능


class ToolError(Exception):
    """LLM에게 is_error=True tool_result로 전달되는 비즈니스 오류."""


def get_member(member_id: str) -> dict:
    with pool.connection() as conn:
        m = conn.execute(
            "SELECT id, name, grade, points, expiring_pts, expire_at"
            " FROM members WHERE id = %s", (member_id,)
        ).fetchone()
    if m is None:
        raise ToolError(f"회원 없음: {member_id}")
    if m["expire_at"]:
        m["expire_in_days"] = (m["expire_at"] - date.today()).days
        m["expire_at"] = m["expire_at"].isoformat()
    return m


def get_purchase_history(member_id: str, category: str | None = None) -> list[dict]:
    sql = (
        "SELECT h.purchased_at, p.id AS product_id, p.name, p.category, p.price"
        " FROM purchase_history h JOIN products p ON p.id = h.product_id"
        " WHERE h.member_id = %s"
    )
    args: list = [member_id]
    if category:
        sql += " AND p.category = %s"
        args.append(category)
    sql += " ORDER BY h.purchased_at DESC LIMIT 20"
    with pool.connection() as conn:
        rows = conn.execute(sql, args).fetchall()
    for r in rows:
        r["purchased_at"] = r["purchased_at"].isoformat()
    return rows


_SORTS = {
    "price_asc": "price ASC",
    "price_desc": "price DESC",
    "repurchase": "repurchase_rate DESC NULLS LAST",
    "relevance": "repurchase_rate DESC NULLS LAST",  # 텍스트 랭킹 없이 재구매율 근사
}


def search_products(
    query: str | None = None,
    category: str | None = None,
    tags: list[str] | None = None,
    max_price: int | None = None,
    min_price: int | None = None,
    in_stock_only: bool = True,
    sort: str = "relevance",
    limit: int = 10,
) -> dict:
    where, args = ["TRUE"], []
    if query:
        # 공백 구분 키워드 AND 매칭 (이름 + 태그 대상)
        for kw in query.split():
            where.append("(name ILIKE %s OR EXISTS (SELECT 1 FROM unnest(tags) t WHERE t ILIKE %s))")
            args += [f"%{kw}%", f"%{kw}%"]
    if category:
        where.append("category = %s")
        args.append(category)
    if tags:
        where.append("tags @> %s")
        args.append(tags)
    if max_price is not None:
        where.append("price <= %s")
        args.append(max_price)
    if min_price is not None:
        where.append("price >= %s")
        args.append(min_price)
    if in_stock_only:
        where.append("stock > 0")

    order = _SORTS.get(sort, _SORTS["relevance"])
    sql_where = " AND ".join(where)
    with pool.connection() as conn:
        total = conn.execute(
            f"SELECT count(*) AS c FROM products WHERE {sql_where}", args
        ).fetchone()["c"]
        rows = conn.execute(
            "SELECT id AS product_id, emoji, name, category, price, tags,"
            "       stock, summary, repurchase_rate"
            f" FROM products WHERE {sql_where} ORDER BY {order}, id LIMIT %s",
            [*args, min(max(limit, 1), 30)],
        ).fetchall()
    return {"total_matched": total, "returned": len(rows), "products": rows}


def get_product_specs(product_ids: list[str]) -> list[dict]:
    with pool.connection() as conn:
        rows = conn.execute(
            "SELECT id AS product_id, emoji, name, category, price, tags,"
            "       stock, specs, repurchase_rate"
            " FROM products WHERE id = ANY(%s)", (product_ids,)
        ).fetchall()
    found = {r["product_id"] for r in rows}
    missing = [p for p in product_ids if p not in found]
    if missing:
        raise ToolError(f"존재하지 않는 상품 id: {missing}")
    return rows


def products_by_ids(product_ids: list[str], check_stock: bool = True) -> list[dict]:
    """상품 검증 조회 — 세션 장바구니(orders.py)가 사용. 쓰기 없음."""
    with pool.connection() as conn:
        prods = conn.execute(
            "SELECT id, name, price, stock FROM products WHERE id = ANY(%s)",
            (product_ids,),
        ).fetchall()
    found = {p["id"] for p in prods}
    missing = [p for p in product_ids if p not in found]
    if missing:
        raise ToolError(f"존재하지 않는 상품 id: {missing}")
    if check_stock:
        out_of_stock = [p["name"] for p in prods if p["stock"] <= 0]
        if out_of_stock:
            raise ToolError(f"재고 없음: {out_of_stock}")
    return prods


def confirm_order(member_id: str, order: dict) -> int:
    """결제 확정 — 유일한 쓰기 경로 (2026-08-27 시나리오 변경).

    orders 기록 + 포인트 차감 + 원장 + 구매이력을 한 트랜잭션으로. 잔여 포인트 반환.
    """
    from datetime import date
    with pool.connection() as conn:
        with conn.transaction():
            member = conn.execute(
                "SELECT points FROM members WHERE id = %s FOR UPDATE", (member_id,)
            ).fetchone()
            if member is None:
                raise ToolError(f"회원 없음: {member_id}")
            if member["points"] < order["points_used"]:
                raise ToolError(
                    f"포인트 상태가 변경되어 확정 불가: 잔여 {member['points']:,}P < "
                    f"사용 예정 {order['points_used']:,}P — 주문을 다시 접수하세요."
                )
            conn.execute(
                "INSERT INTO orders (id, member_id, total, points_used,"
                " extra_amount, payment_method, status)"
                " VALUES (%s, %s, %s, %s, %s, %s, %s)",
                (order["order_id"], member_id, order["total"], order["points_used"],
                 order["extra_amount"], order["payment_method"], "결제 완료(데모)"),
            )
            balance_after = conn.execute(
                "UPDATE members SET points = points - %s WHERE id = %s RETURNING points",
                (order["points_used"], member_id),
            ).fetchone()["points"]
            if order["points_used"] > 0:
                conn.execute(
                    "INSERT INTO point_ledger (member_id, delta, reason) VALUES (%s, %s, %s)",
                    (member_id, -order["points_used"], f"결제확정 {order['order_id']}"),
                )
            for item in order["items"]:
                conn.execute(
                    "INSERT INTO purchase_history (member_id, product_id, purchased_at)"
                    " VALUES (%s, %s, %s)",
                    (member_id, item["product_id"], date.today()),
                )
    return balance_after


def current_points(member_id: str) -> int:
    with pool.connection() as conn:
        row = conn.execute(
            "SELECT points FROM members WHERE id = %s", (member_id,)
        ).fetchone()
    return row["points"] if row else 0
