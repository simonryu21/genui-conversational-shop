"""데모 상태 초기화 — 주문/장바구니/원장 리셋, 포인트 180,000P 복원 (상품 데이터는 유지)."""
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app import db  # noqa: E402

with db.pool.connection() as conn:
    conn.execute("DELETE FROM point_ledger WHERE reason <> '2026년 복지포인트 지급'")
    conn.execute("DELETE FROM orders")
    conn.execute("DELETE FROM carts")
    # 결제 확정으로 추가된 구매이력 제거 (시드 3건은 과거 날짜라 유지됨)
    conn.execute("DELETE FROM purchase_history WHERE purchased_at >= '2026-08-27'")
    conn.execute("UPDATE members SET points = 180000 WHERE id = 'm-001'")
    conn.commit()
print("데모 초기화 완료 — points:", db.current_points("m-001"))
