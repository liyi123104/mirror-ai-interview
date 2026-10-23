from typing import Any, Optional

from fastapi import Header, HTTPException

from app.config import settings


def ok(data: Any = None) -> dict:
    return {"code": 0, "message": "ok", "data": data}


def fail(code: int, message: str) -> dict:
    return {"code": code, "message": message, "data": None}


async def verify_token(x_internal_token: Optional[str] = Header(default=None)) -> None:
    if x_internal_token != settings.internal_token:
        raise HTTPException(status_code=401, detail="内部令牌不匹配")