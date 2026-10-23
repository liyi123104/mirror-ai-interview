from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.common import ok, verify_token
from app.services.interviewer import follow_up, next_question, should_follow_up

router = APIRouter(prefix="/ai/interview", dependencies=[Depends(verify_token)])


class NextRequest(BaseModel):
    sessionId: str
    job: str
    resume: dict = {}
    requirements: list[dict] = []
    asked: list[str] = []
    lastQuestion: str = ""
    lastAnswer: str = ""
    depth: int = 0
    maxDepth: int = 2


@router.post("/next")
def next_api(req: NextRequest):
    if req.lastQuestion and req.lastAnswer:
        if should_follow_up(req.lastAnswer, req.depth, req.maxDepth):
            f = follow_up(req.job, req.lastQuestion, req.lastAnswer)
            if f["type"] == "follow_up":
                return ok(f)

    return ok(next_question(req.job, req.resume, req.requirements, req.asked))
