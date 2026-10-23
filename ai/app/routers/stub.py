from fastapi import APIRouter, Depends, File, UploadFile

from app.common import ok, verify_token

router = APIRouter(prefix="/ai", dependencies=[Depends(verify_token)])

FAKE_USAGE = {"tokensIn": 100, "tokensOut": 20, "cost": 0.001}


@router.post("/resume/parse")
async def resume_parse(file: UploadFile = File(...)):
    return ok({
        "name": "张三",
        "phone": "13800138000",
        "email": "zhang@example.com",
        "education": "本科 某某大学 计算机",
        "projects": [{"name": "订单系统", "tech": ["Redis", "MySQL"], "desc": "高并发下单"}],
        "skills": ["Java", "MySQL", "Redis"],
        "needsReview": False,
        "usage": FAKE_USAGE,
    })


@router.post("/jd/parse")
def jd_parse(payload: dict):
    return ok({
        "title": "Java 后端工程师",
        "requirements": [
            {"id": "R1", "text": "熟悉 JVM 内存模型", "type": "must"},
            {"id": "R2", "text": "有高并发经验", "type": "must"},
            {"id": "R3", "text": "了解 K8s", "type": "nice"},
        ],
    })


@router.post("/question/index")
def question_index(payload: dict):
    return ok({"indexed": len(payload.get("questions", [])), "failed": 0})


@router.post("/question/search")
def question_search(payload: dict):
    return ok({"items": [
        {"id": "q1", "stem": "【假数据】讲讲 Redis 缓存穿透", "score": 0.82}
    ]})


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