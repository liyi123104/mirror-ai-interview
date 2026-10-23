from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.common import ok, verify_token
from app.services.scorer import DIMENSIONS, score_answer

router = APIRouter(prefix="/ai", dependencies=[Depends(verify_token)])


class ScoreRequest(BaseModel):
    question: str
    answer: str
    dimensions: list[str] | None = None


@router.post("/score")
def score(req: ScoreRequest):
    dims = req.dimensions or DIMENSIONS
    invalid = [d for d in dims if d not in DIMENSIONS]
    if invalid:
        return ok({"error": f"不支持的维度：{invalid}"})

    if not req.answer.strip():
        return ok({"error": "回答是空的，没法评分"})

    return ok(score_answer(req.question, req.answer, dims))
