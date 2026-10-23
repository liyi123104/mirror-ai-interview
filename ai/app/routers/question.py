from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.common import ok, verify_token
from app.services import vector_store

router = APIRouter(prefix="/ai/question", dependencies=[Depends(verify_token)])


class IndexRequest(BaseModel):
    questions: list[dict]


class SearchRequest(BaseModel):
    query: str
    job: str | None = None
    topK: int = 5


@router.post("/index")
def index(req: IndexRequest):
    return ok(vector_store.index(req.questions))


@router.delete("/index/{qid}")
def remove(qid: str):
    vector_store.remove(qid)
    return ok(None)


@router.post("/search")
def search(req: SearchRequest):
    return ok({"items": vector_store.search(req.query, req.job, req.topK)})


@router.get("/index/size")
def size():
    return ok({"size": vector_store.size()})
