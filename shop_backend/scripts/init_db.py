"""shop_db 초기화 — CREATE DATABASE + schema.sql + seed.sql (멱등: 재실행 시 전체 리셋).

사용법:  python scripts/init_db.py
전제:    .env의 DATABASE_URL (…/shop_db), 로컬 PostgreSQL 기동 중
"""
import os
import sys
from pathlib import Path

import psycopg
from psycopg import conninfo
from dotenv import load_dotenv

sys.stdout.reconfigure(encoding="utf-8")

BASE = Path(__file__).resolve().parents[1]
load_dotenv(BASE / ".env")

DATABASE_URL = os.environ["DATABASE_URL"]
params = conninfo.conninfo_to_dict(DATABASE_URL)
target_db = params["dbname"]


def ensure_database() -> None:
    """관리용 postgres DB로 접속해 대상 DB가 없으면 생성한다."""
    admin = dict(params, dbname="postgres")
    with psycopg.connect(**admin, autocommit=True) as conn:
        exists = conn.execute(
            "SELECT 1 FROM pg_database WHERE datname = %s", (target_db,)
        ).fetchone()
        if exists:
            print(f"[init_db] database '{target_db}' 이미 존재")
        else:
            conn.execute(f'CREATE DATABASE "{target_db}"')
            print(f"[init_db] database '{target_db}' 생성")


def apply_sql(conn: psycopg.Connection, path: Path) -> None:
    sql = path.read_text(encoding="utf-8")
    conn.execute(sql)  # 파라미터 없는 execute는 simple protocol — 다중 문장 허용
    print(f"[init_db] {path.name} 적용 완료")


def summarize(conn: psycopg.Connection) -> None:
    rows = conn.execute(
        "SELECT category, count(*), min(price), max(price)"
        " FROM products GROUP BY category ORDER BY category"
    ).fetchall()
    print("\n[요약] products 카테고리별:")
    total = 0
    for cat, cnt, lo, hi in rows:
        total += cnt
        print(f"  {cat:>4}: {cnt:3}종  ({lo:,}P ~ {hi:,}P)")
    print(f"  합계: {total}종")

    tuna = conn.execute(
        "SELECT count(*) FROM products WHERE '참치캔' = ANY(tags)"
    ).fetchone()[0]
    print(f"  참치캔 태그: {tuna}종 (데모 대사 기준 32종이어야 함)")

    m = conn.execute(
        "SELECT name, points, expiring_pts, expire_at FROM members WHERE id='m-001'"
    ).fetchone()
    print(f"  회원: {m[0]} / 잔여 {m[1]:,}P / 소멸예정 {m[2]:,}P ({m[3]})")

    h = conn.execute("SELECT count(*) FROM purchase_history").fetchone()[0]
    print(f"  구매 이력: {h}건")


def main() -> None:
    ensure_database()
    with psycopg.connect(**params) as conn:
        apply_sql(conn, BASE / "scripts" / "schema.sql")
        apply_sql(conn, BASE / "scripts" / "seed.sql")
        conn.commit()
        summarize(conn)
    print("\n[init_db] 완료")


if __name__ == "__main__":
    main()
