from fastapi import APIRouter, Depends

from app.common import ok, verify_token

router = APIRouter(prefix="/ai", dependencies=[Depends(verify_token)])

FAKE_USAGE = {"tokensIn": 100, "tokensOut": 20, "cost": 0.001}


@router.post("/interview/next")
def interview_next(payload: dict):
    answer = payload.get("lastAnswer", "")

    if answer:
        return ok({
            "type": "follow_up",
            "stem": f"【假数据】你提到「{answer[:8]}」，能再展开说说吗？",
            "basedOn": "",
            "dimension": "技术深度",
            "usage": FAKE_USAGE,
        })

    return ok({
        "type": "new_question",
        "stem": "【假数据】请介绍你最近做的一个项目",
        "basedOn": "简历项目「订单系统」",
        "dimension": "技术深度",
        "usage": FAKE_USAGE,
    })


@router.post("/score")
def score(payload: dict):
    return ok({
        "dimensions": [
            {"dimension": "技术深度", "score": 3.0, "confidence": "high",
             "reason": "说了用法，没提取舍", "evidence": "用 Redis 做缓存",
             "raw": [3, 3], "diff": 0}
        ],
        "total": 3.0,
        "usage": FAKE_USAGE,
    })


@router.post("/report/item")
def report_item(payload: dict):
    return ok({
        "gap": "缺了对缓存穿透的处理",
        "betterAnswer": "先讲穿透是什么，再给两种解法",
        "usage": FAKE_USAGE,
    })