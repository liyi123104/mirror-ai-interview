"""评分器：单次评分、双次评分、证据校验都在这里。

三个实验开关（Day 20 用它们测每一步的贡献）：
    SCORE_DOUBLE=0     关掉双次评分
    SCORE_KEYPOINTS=0  关掉“先列关键点再打分”
    SCORE_EVIDENCE=0   关掉证据校验
"""

import os
import re
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from app.services.llm import chat_json
from app.services.prompts import fill, load

DIMENSIONS = ["技术深度", "逻辑结构", "表达清晰", "岗位匹配"]

USE_DOUBLE = os.getenv("SCORE_DOUBLE", "1") == "1"
USE_KEYPOINTS = os.getenv("SCORE_KEYPOINTS", "1") == "1"
USE_EVIDENCE = os.getenv("SCORE_EVIDENCE", "1") == "1"
# 正常情况下必须保持 0；只有做“温度有没有影响”的对比实验时才调大
TEMPERATURE = float(os.getenv("SCORE_TEMPERATURE", "0"))
# 四维同时打几个：并发太高容易被限流
SCORE_WORKERS = int(os.getenv("SCORE_WORKERS", "4"))

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
    """四个维度并发打分，再把每个维度的两次结果合成一个分。

    为什么要并发：四维双评是 8 次调用，串行要十几秒，并发后 3–5 秒。
    """
    dims = dimensions or DIMENSIONS
    workers = max(1, min(len(dims), SCORE_WORKERS))

    def score_dim(dim: str) -> dict:
        cost = 0.0
        tin = 0
        tout = 0

        def call() -> dict:
            nonlocal cost, tin, tout
            r = score_once(question, answer, dim)
            cost += r["usage"].cost
            tin += r["usage"].tokens_in
            tout += r["usage"].tokens_out
            return r

        s1 = call()
        s2 = call() if USE_DOUBLE else s1

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

        return {
            "dimension": dim,
            "score": final,
            "confidence": confidence,
            "reason": s1["reason"],
            "evidence": s1["evidence"],
            "raw": [a, b],
            "diff": diff,
            "_cost": cost,
            "_in": tin,
            "_out": tout,
        }

    with ThreadPoolExecutor(max_workers=workers) as pool:
        results = list(pool.map(score_dim, dims))

    total_cost = sum(r.pop("_cost") for r in results)
    tokens_in = sum(r.pop("_in") for r in results)
    tokens_out = sum(r.pop("_out") for r in results)

    total = round(sum(r["score"] for r in results) / len(results), 2)

    return {
        "dimensions": results,
        "total": total,
        "usage": {"tokensIn": tokens_in, "tokensOut": tokens_out,
                  "cost": round(total_cost, 6)},
    }
