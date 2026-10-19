-- GenUI 복지몰 데모 스키마 (설계: docs/genui_llm_shop_design.md §4)
-- 재실행 시 전체 리셋 (데모 DB 전용 — 운영 데이터 없음)

DROP TABLE IF EXISTS point_ledger CASCADE;
DROP TABLE IF EXISTS orders CASCADE;
DROP TABLE IF EXISTS cart_items CASCADE;
DROP TABLE IF EXISTS carts CASCADE;
DROP TABLE IF EXISTS purchase_history CASCADE;
DROP TABLE IF EXISTS products CASCADE;
DROP TABLE IF EXISTS members CASCADE;
DROP SEQUENCE IF EXISTS order_seq;

CREATE TABLE members (
    id            TEXT PRIMARY KEY,          -- 'm-001'
    name          TEXT NOT NULL,
    grade         TEXT NOT NULL,
    points        INT  NOT NULL,
    expiring_pts  INT  NOT NULL DEFAULT 0,
    expire_at     DATE
);

CREATE TABLE products (
    id        TEXT PRIMARY KEY,
    emoji     TEXT NOT NULL DEFAULT '🛍️',
    name      TEXT NOT NULL,
    category  TEXT NOT NULL,                 -- 식품 | 캠핑 | 가전 | 리빙 | 선물 | 생필품
    price     INT  NOT NULL,
    tags      TEXT[] NOT NULL DEFAULT '{}',
    stock     INT  NOT NULL DEFAULT 100,
    summary   TEXT,                          -- 추천 근거 소재 (실데이터는 NULL — LLM이 직접 작성)
    specs     JSONB NOT NULL DEFAULT '{}',
    repurchase_rate INT,                     -- 재구매율 % (정렬용)
    source    TEXT NOT NULL DEFAULT 'seed'   -- seed | chamgagyeok | openfoodfacts
);

CREATE INDEX idx_products_category ON products (category);
CREATE INDEX idx_products_price    ON products (price);
CREATE INDEX idx_products_tags     ON products USING GIN (tags);

CREATE TABLE purchase_history (
    id           SERIAL PRIMARY KEY,
    member_id    TEXT REFERENCES members(id),
    product_id   TEXT REFERENCES products(id),
    purchased_at DATE NOT NULL
);

CREATE TABLE carts (
    id         SERIAL PRIMARY KEY,
    member_id  TEXT REFERENCES members(id),
    status     TEXT NOT NULL DEFAULT 'draft',   -- draft | ordered
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE cart_items (
    cart_id    INT  REFERENCES carts(id) ON DELETE CASCADE,
    product_id TEXT REFERENCES products(id),
    price      INT NOT NULL,                    -- 담은 시점 가격 스냅샷
    PRIMARY KEY (cart_id, product_id)
);

CREATE SEQUENCE order_seq START WITH 1041;

CREATE TABLE orders (
    id             TEXT PRIMARY KEY,            -- 'WF-2026-1041'
    member_id      TEXT REFERENCES members(id),
    cart_id        INT REFERENCES carts(id),
    total          INT NOT NULL,
    points_used    INT NOT NULL DEFAULT 0,      -- 복지포인트 사용분
    extra_amount   INT NOT NULL DEFAULT 0,      -- 부족분 (신용카드/간편결제 — 데모: 실결제 없음)
    payment_method TEXT,                        -- 신용카드 | 간편결제 (extra_amount>0일 때)
    status         TEXT NOT NULL DEFAULT '결제 대기',
    created_at     TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE point_ledger (
    id         SERIAL PRIMARY KEY,
    member_id  TEXT REFERENCES members(id),
    delta      INT  NOT NULL,
    reason     TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);
