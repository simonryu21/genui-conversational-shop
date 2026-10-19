"""FastAPI 앱 — CORS + DB 풀 수명주기 (설계 §3-2)."""
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .db import pool
from .routes import router


@asynccontextmanager
async def lifespan(app: FastAPI):
    yield  # 풀은 db.py import 시점에 열림
    pool.close()


app = FastAPI(title="genui-shop-backend", lifespan=lifespan)

# 로컬 데모 전용 — flutter run이 매번 임의 포트를 쓰므로 전체 허용
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router)
