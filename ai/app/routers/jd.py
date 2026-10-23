from fastapi import APIRouter, Depends
from pydantic import BaseModel

from app.common import ok, verify_token
from app.services.llm import chat_json
from app.services.prompts import fill, load

router = APIRouter(prefix="/ai/jd", dependencies=[Depends(verify_token)])


class JdRequest(BaseModel):
    text: str


@router.post("/parse")
def parse(req: JdRequest):
    if len(req.text.strip()) < 10:
        return ok({"title": "", "requirements": []})

    prompt = fill(load("jd_extract"), {"text": req.text[:2500]})
    data, usage = chat_json([{"role": "user", "content": prompt}], temperature=0.0)

    reqs = data.get("requirements") or []
    cleaned = []
    for i, r in enumerate(reqs[:10], start=1):
        text = (r.get("text") or "").strip()
        if not text:
            continue
        cleaned.append({
            "id": f"R{i}",
            "text": text,
            "type": "must" if r.get("type") == "must" else "nice",
        })

    return ok({
        "title": (data.get("title") or "").strip(),
        "requirements": cleaned,
        "usage": {"tokensIn": usage.tokens_in,
                  "tokensOut": usage.tokens_out,
                  "cost": round(usage.cost, 6)},
    })
