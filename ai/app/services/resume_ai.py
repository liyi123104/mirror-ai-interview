from app.services.llm import chat_json
from app.services.prompts import fill, load


def extract_by_llm(text: str) -> dict:
    """规则抽不出来时的兜底：让模型返回结构化 JSON。"""
    prompt = fill(load("resume_extract"), {"text": text[:3000]})
    data, usage = chat_json([{"role": "user", "content": prompt}], temperature=0.0)

    data["usage"] = {
        "tokensIn": usage.tokens_in,
        "tokensOut": usage.tokens_out,
        "cost": round(usage.cost, 6),
    }
    return data
