"""실데이터 수집 → products upsert (설계: docs/genui_llm_shop_design.md §4).

소스 1) 한국소비자원 참가격 openAPI — DATA_GO_KR_API_KEY 필요, 키 미동기화(resultCode!=00) 시 자동 스킵
소스 2) Open Food Facts — 인증 불필요, 한국 등록 식품

사용법:  python scripts/fetch_seed_data.py [--off-limit 400]
재실행 안전: ON CONFLICT (id) DO UPDATE (가격·재고는 기존 값 유지 — 데모 중 수동 변경 보호)
"""
import argparse
import os
import re
import sys
import time
import zlib
import xml.etree.ElementTree as ET
from datetime import date, timedelta
from pathlib import Path

import httpx
import psycopg
from dotenv import load_dotenv

sys.stdout.reconfigure(encoding="utf-8")

BASE = Path(__file__).resolve().parents[1]
load_dotenv(BASE / ".env")

DATABASE_URL = os.environ["DATABASE_URL"]
CG_KEY = os.environ.get("DATA_GO_KR_API_KEY", "")
CG_BASE = "http://openapi.price.go.kr/openApiImpl/ProductPriceInfoService"
OFF_URL = "https://world.openfoodfacts.org/api/v2/search"

UPSERT = """
INSERT INTO products (id, emoji, name, category, price, tags, stock, specs, repurchase_rate, source)
VALUES (%(id)s, %(emoji)s, %(name)s, %(category)s, %(price)s, %(tags)s, 100, %(specs)s, %(rate)s, %(source)s)
ON CONFLICT (id) DO UPDATE SET
  name = EXCLUDED.name, category = EXCLUDED.category, tags = EXCLUDED.tags,
  specs = EXCLUDED.specs, source = EXCLUDED.source
"""

# 이름/분류 키워드 → (이모지, 태그) — 순서 우선 매칭
KEYWORD_MAP = [
    ("라면",   "🍜", ["면류"]),      ("김치",  "🥬", ["반찬"]),
    ("참치",   "🐟", ["참치캔"]),    ("우유",  "🥛", ["유제품"]),
    ("치즈",   "🧀", ["유제품"]),    ("요구르트", "🥛", ["유제품"]),
    ("커피",   "☕", ["음료"]),      ("음료",  "🥤", ["음료"]),
    ("주스",   "🧃", ["음료"]),      ("차",    "🍵", ["음료"]),
    ("과자",   "🍪", ["간식"]),      ("스낵",  "🍿", ["간식"]),
    ("초콜릿", "🍫", ["간식"]),      ("사탕",  "🍬", ["간식"]),
    ("아이스", "🍦", ["간식"]),      ("빵",    "🍞", ["베이커리"]),
    ("쌀",     "🌾", ["주식"]),      ("햇반",  "🍚", ["주식","간편식"]),
    ("만두",   "🥟", ["간편식"]),    ("피자",  "🍕", ["간편식"]),
    ("소시지", "🌭", ["간편식"]),    ("햄",    "🥓", ["간편식"]),
    ("계란",   "🥚", ["신선식품"]),  ("두부",  "🥡", ["신선식품"]),
    ("기름",   "🫒", ["조미료"]),    ("간장",  "🧂", ["조미료"]),
    ("고추장", "🌶️", ["조미료"]),    ("된장",  "🥣", ["조미료"]),
    ("설탕",   "🧂", ["조미료"]),    ("소금",  "🧂", ["조미료"]),
    ("샴푸",   "🧴", ["생활용품"]),  ("세제",  "🧼", ["생활용품"]),
    ("치약",   "🪥", ["생활용품"]),  ("휴지",  "🧻", ["생활용품"]),
    ("물티슈", "🧻", ["생활용품"]),  ("기저귀", "👶", ["육아"]),
]
NONFOOD_TAGS = {"생활용품", "육아"}


def enrich(name: str) -> tuple[str, list[str], str]:
    """이름에서 (이모지, 태그, 카테고리) 유추."""
    tags: list[str] = []
    emoji = "🛒"
    for kw, em, ts in KEYWORD_MAP:
        if kw in name:
            emoji = em
            tags.extend(t for t in ts if t not in tags)
            break
    if re.search(r"저염|라이트|덜\s*짠", name):
        tags.append("저염")
    if re.search(r"대용량|박스|번들|×\s*2[0-9]", name):
        tags.append("대용량")
    category = "생필품" if any(t in NONFOOD_TAGS for t in tags) else "식품"
    return emoji, tags, category


def pseudo(seed: str, lo: int, hi: int) -> int:
    """결정적 의사난수 (재실행해도 같은 값)."""
    return lo + zlib.crc32(seed.encode()) % (hi - lo + 1)


# ---------------------------------------------------------------------------
# 소스 1 — 한국소비자원 참가격
# ---------------------------------------------------------------------------
def find_ci(root: ET.Element, name: str) -> ET.Element | None:
    """태그 대소문자 무시 탐색. 주의: ET 요소는 자식이 없으면 falsy — `or` 폴백 금지."""
    name = name.lower()
    for el in root.iter():
        if el.tag.lower() == name:
            return el
    return None


def cg_get(client: httpx.Client, op: str, **query) -> ET.Element | None:
    qs = "&".join(f"{k}={v}" for k, v in query.items())
    url = f"{CG_BASE}/{op}.do?ServiceKey={CG_KEY}" + (f"&{qs}" if qs else "")
    resp = client.get(url, timeout=60)
    resp.raise_for_status()
    root = ET.fromstring(resp.text)
    code_el = find_ci(root, "resultCode")
    code = (code_el.text or "").strip() if code_el is not None else "??"
    if code != "00":
        msg_el = find_ci(root, "resultMsg")
        print(f"[참가격] {op} resultCode={code} ({msg_el.text if msg_el is not None else ''})")
        return None
    return root


def item_text(item: ET.Element, *names: str) -> str:
    """대소문자 표기가 문서/실응답 간 다른 필드를 관대하게 조회."""
    lowered = {child.tag.lower(): (child.text or "").strip() for child in item}
    for n in names:
        if n.lower() in lowered:
            return lowered[n.lower()]
    return ""


def last_fridays(n: int = 4):
    d = date.today()
    d -= timedelta(days=(d.weekday() - 4) % 7)  # 최근 금요일
    for _ in range(n):
        yield d.strftime("%Y%m%d")
        d -= timedelta(days=7)


def fetch_chamgagyeok(conn: psycopg.Connection) -> int:
    if not CG_KEY:
        print("[참가격] DATA_GO_KR_API_KEY 없음 — 스킵")
        return 0
    with httpx.Client() as client:
        # 1) 소분류 코드 → 분류명
        std = cg_get(client, "getStandardInfoSvc", classCode="AL")
        if std is None:
            print("[참가격] 인증키 미동기화 또는 오류 — 이번 실행은 스킵 (재실행 시 재시도)")
            return 0
        cls_name = {}
        for it in std.iter():
            if it.tag.lower().endswith("stdinfovo") or it.tag.lower() == "item":
                code = item_text(it, "code")
                if code:
                    cls_name[code] = item_text(it, "codeName", "codename")

        # 2) 전체 상품 목록
        prod_root = cg_get(client, "getProductInfoSvc")
        if prod_root is None:
            return 0
        goods = {}
        for it in prod_root.findall(".//item"):
            gid = item_text(it, "goodId", "goodid")
            gname = item_text(it, "goodName", "goodname")
            if gid and gname:
                goods[gid] = {
                    "name": gname,
                    "cls": cls_name.get(item_text(it, "goodSmlclsCode", "goodsmlclscode"), ""),
                }
        print(f"[참가격] 상품 목록 {len(goods)}건")

        # 3) 판매점 → 대형마트 2곳 선정
        store_root = cg_get(client, "getStoreInfoSvc")
        if store_root is None:
            return 0
        marts = []
        for it in store_root.findall(".//item") or store_root.iter():
            ename = item_text(it, "entpName", "entpname")
            eid = item_text(it, "entpId", "entpid")
            if eid and any(m in ename for m in ("이마트", "홈플러스", "롯데마트")):
                marts.append(eid)
        marts = marts[:2]
        print(f"[참가격] 가격 조회 대상 업체: {marts}")

        # 4) 최근 금요일 기준 가격 (없으면 한 주씩 소급, 최대 4주)
        prices: dict[str, list[int]] = {}
        for day in last_fridays():
            for eid in marts:
                pr = cg_get(client, "getProductPriceInfoSvc", goodInspectDay=day, entpId=eid)
                if pr is None:
                    continue
                for it in pr.findall(".//item"):
                    gid = item_text(it, "goodId", "goodid")
                    p = item_text(it, "goodPrice", "goodprice")
                    if gid and p.isdigit():
                        prices.setdefault(gid, []).append(int(p))
            if prices:
                print(f"[참가격] 조사일 {day} 가격 {len(prices)}상품")
                break

    n = 0
    with conn.cursor() as cur:
        for gid, info in goods.items():
            if gid not in prices:
                continue  # 해당 조사일 가격 없는 상품은 미시드
            avg = round(sum(prices[gid]) / len(prices[gid]) / 100) * 100
            emoji, tags, category = enrich(info["name"])
            if info["cls"]:
                tags = [info["cls"], *tags]
            cur.execute(UPSERT, {
                "id": f"cg_{gid}", "emoji": emoji, "name": info["name"],
                "category": category, "price": max(avg, 500),
                "tags": tags, "specs": "{}",
                "rate": pseudo(gid, 55, 95), "source": "chamgagyeok",
            })
            n += 1
    conn.commit()
    return n


# ---------------------------------------------------------------------------
# 소스 2 — Open Food Facts (한국 등록 식품)
# ---------------------------------------------------------------------------
def fetch_off(conn: psycopg.Connection, limit: int) -> int:
    n, page = 0, 1
    with httpx.Client(headers={"User-Agent": "genui-shop-demo/1.0"}) as client, conn.cursor() as cur:
        while n < limit and page <= 40:
            # OFF 검색 API는 분당 10회 제한 — 페이지 간 대기 + 401/429/503 재시도
            # (제한 초과가 지속되면 401을 주기도 함). 실패해도 수집분은 보존.
            for attempt in range(5):
                resp = client.get(OFF_URL, params={
                    "countries_tags": "south-korea", "page_size": 100, "page": page,
                    "fields": "code,product_name,product_name_ko,brands,quantity",
                }, timeout=60)
                if resp.status_code in (401, 429, 503):
                    wait = 30 * (attempt + 1)
                    print(f"[OFF] page {page} → {resp.status_code}, {wait}s 대기 후 재시도", flush=True)
                    time.sleep(wait)
                    continue
                resp.raise_for_status()
                break
            else:
                print(f"[OFF] page {page} 재시도 초과 — 수집 중단 (지금까지 {n}건 보존)", flush=True)
                break
            products = resp.json().get("products", [])
            print(f"[OFF] page {page}: {len(products)}건 수신 (누적 upsert {n})", flush=True)
            time.sleep(8)
            if not products:
                break
            for p in products:
                name = (p.get("product_name_ko") or p.get("product_name") or "").strip()
                code = p.get("code", "")
                # 품질 필터: 이름 2자 이상 + 한글 포함 건만 (영문 전용/빈 이름 제외)
                if not code or len(name) < 2 or not re.search(r"[가-힣]", name):
                    continue
                brand = (p.get("brands") or "").split(",")[0].strip()
                qty = (p.get("quantity") or "").strip()
                full = " ".join(x for x in (brand, name) if x)
                if qty and qty not in full:
                    full += f" ({qty})"
                if len(full) > 70:
                    full = full[:70]
                emoji, tags, category = enrich(full)
                cur.execute(UPSERT, {
                    "id": f"off_{code}", "emoji": emoji, "name": full,
                    "category": category, "price": pseudo(code, 15, 350) * 100,
                    "tags": tags, "specs": "{}",
                    "rate": pseudo(code + "r", 55, 95), "source": "openfoodfacts",
                })
                n += 1
                if n >= limit:
                    break
            conn.commit()  # 페이지 단위 커밋 — 중단돼도 수집분 보존
            page += 1
    conn.commit()
    return n


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--off-limit", type=int, default=400)
    args = ap.parse_args()

    with psycopg.connect(DATABASE_URL) as conn:
        cg = fetch_chamgagyeok(conn)
        off = fetch_off(conn, args.off_limit)
        total = conn.execute("SELECT count(*) FROM products").fetchone()[0]
        by_src = conn.execute(
            "SELECT source, count(*) FROM products GROUP BY source ORDER BY source"
        ).fetchall()
    print(f"\n[완료] 참가격 {cg}건 / OFF {off}건 upsert")
    print(f"[요약] products 총 {total}종 — " + ", ".join(f"{s}:{c}" for s, c in by_src))


if __name__ == "__main__":
    main()
