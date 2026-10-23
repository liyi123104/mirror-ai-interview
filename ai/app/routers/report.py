from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.common import ok, verify_token
from app.services.llm import chat_json
from app.services.prompts import fill, load

router = APIRouter(prefix="/ai/report", dependencies=[Depends(verify_token)])

ZERO_USAGE = {"tokensIn": 0, "tokensOut": 0, "cost": 0.0}


class ItemRequest(BaseModel):
    question: str
    basedOn: str = ""
    answer: str = ""
    score: int = 3


@router.post("/item")
def item(req: ItemRequest):
    prompt = fill(load("report_item"), {
        "question": req.question,
        "basedOn": req.basedOn or "（未标注）",
        "answer": req.answer or "（没有作答）",
        "score": str(req.score),
    })

    try:
        data, usage = chat_json([{"role": "user", "content": prompt}], temperature=0.5)
        return ok({
            "gap": (data.get("gap") or "").strip(),
            "betterAnswer": (data.get("betterAnswer") or "").strip(),
            "usage": {"tokensIn": usage.tokens_in,
                      "tokensOut": usage.tokens_out,
                      "cost": round(usage.cost, 6)},
        })
    except Exception:
        # 单条失败不能让整份报告挂掉
        return ok({
            "gap": "复盘生成失败，请回看原文对照口径",
            "betterAnswer": "",
            "usage": ZERO_USAGE,
        })
