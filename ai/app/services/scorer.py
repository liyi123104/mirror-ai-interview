"""评分器：单次评分、双次评分、证据校验都在这里。

三个实验开关（Day 20 用它们测每一步的贡献）：
    SCORE_DOUBLE=0     关掉双次评分
    SCORE_KEYPOINTS=0  关掉“先列关键点再打分”
    SCORE_EVIDENCE=0   关掉证据校验
"""

import os
import re
from pathlib import Path

from app.services.llm import chat_json
from app.services.prompts import fill, load

DIMENSIONS = ["技术深度", "逻辑结构", "表达清晰", "岗位匹配"]

USE_DOUBLE = os.getenv("SCORE_DOUBLE", "1") == "1"
USE_KEYPOINTS = os.getenv("SCORE_KEYPOINTS", "1") == "1"
USE_EVIDENCE = os.getenv("SCORE_EVIDENCE", "1") == "1"
# 正常情况下必须保持 0；只有做“温度有没有影响”的对比实验时才调大
TEMPERATURE = float(os.getenv("SCORE_TEMPERATURE", "0"))

_rubric_cache: str | None = None
_STEPS_RE = re.compile(r"<!--STEPS-->.*?<!--/STEPS-->\s*", re.S)


def rubric() -> str:
    global _rubric_cache
    if _rubric_cache is None:
        path = Path(__file__).resolve().parent.parent.parent / "prompts" / "rubric.md"
        _rubric_cache = path.read_text(encoding="utf-8")
    return _rubric_cache


def _prompt(question: str, answer: str, dimension: str) -> str:
    template = load("score")
    if not USE_KEYPOINTS:
        template = _STEPS_RE.sub("", template)
    return fill(template, {
        "question": question,
        "dimension": dimension,
        "rubric": rubric(),
        "answer": answer,
    })


def score_once(question: str, answer: str, dimension: str) -> dict:
    data, usage = chat_json(
        [{"role": "user", "content": _prompt(question, answer, dimension)}],
        temperature=TEMPERATURE,
    )

    try:
        score = int(round(float(data.get("score", 3))))
    except (TypeError, ValueError):
        score = 3
    score = max(1, min(5, score))

    return {
        "dimension": dimension,
        "score": score,
        "reason": (data.get("reason") or "").strip(),
        "evidence": (data.get("evidence") or "").strip(),
        "covered": (data.get("covered") or "").strip(),
        "usage": usage,
    }


def validate_evidence(evidence: str, answer: str) -> bool:
    """证据必须是回答里的原文。允许空白差异，不允许改写。"""
    if not evidence or len(evidence.strip()) < 6:
        return False

    clean_e = "".join(evidence.split())
    clean_a = "".join(answer.split())
    return clean_e[:12] in clean_a


def score_answer(question: str, answer: str, dimensions: list[str] | None = None) -> dict:
    dims = dimensions or DIMENSIONS
    results = []
    total_cost = 0.0
    tokens_in = 0
    tokens_out = 0

    def call() -> dict:
        nonlocal total_cost, tokens_in, tokens_out
        r = score_once(question, answer, dim)  # type: ignore[name-defined]
        total_cost += r["usage"].cost
        tokens_in += r["usage"].tokens_in
        tokens_out += r["usage"].tokens_out
        return r

    for dim in dims:
        s1 = call()
        if USE_DOUBLE:
            s2 = call()
        else:
            s2 = s1

        a, b = s1["score"], s2["score"]
        diff = abs(a - b)

        if diff >= 3:
            s3 = call()
            final = sorted([a, b, s3["score"]])[1]
            confidence = "low"
        elif diff == 2:
            final = round((a + b) / 2, 1)
            confidence = "mid"
        else:
            final = round((a + b) / 2, 1)
            confidence = "high"

        # 两次证据都对不上原文，说明可能在编依据
        if USE_EVIDENCE and not validate_evidence(s1["evidence"], answer) \
                and not validate_evidence(s2["evidence"], answer):
            confidence = "low"

        results.append({
            "dimension": dim,
            "score": final,
            "confidence": confidence,
            "reason": s1["reason"],
            "evidence": s1["evidence"],
            "raw": [a, b],
            "diff": diff,
        })

    total = round(sum(r["score"] for r in results) / len(results), 2)

    return {
        "dimensions": results,
        "total": total,
        "usage": {"tokensIn": tokens_in, "tokensOut": tokens_out,
                  "cost": round(total_cost, 6)},
    }
