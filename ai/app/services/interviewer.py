from app.services.llm import chat_json
from app.services.prompts import fill, load
from app.services.vector_store import search

MIN_LEN = 50


def _resume_text(resume: dict) -> str:
    parts = []
    if resume.get("education"):
        parts.append(f"学历：{resume['education']}")
    for p in (resume.get("projects") or [])[:3]:
        tech = "、".join(p.get("tech") or [])
        parts.append(f"项目：{p.get('name')}（{tech}）{p.get('desc', '')}")
    if resume.get("skills"):
        parts.append("技能：" + "、".join(resume["skills"][:12]))
    return "\n".join(parts) or "（简历信息较少）"


def _req_text(reqs: list[dict]) -> str:
    if not reqs:
        return "（未提供）"
    return "\n".join(f"[{r.get('id', '')}] {r.get('text', '')}" for r in reqs)


def next_question(job: str, resume: dict, reqs: list[dict], asked: list[str]) -> dict:
    prompt = fill(load("question_new"), {
        "job": job,
        "resume": _resume_text(resume),
        "requirements": _req_text(reqs),
        "asked": "\n".join(asked) if asked else "（还没有问过）",
    })

    # 题库检索只做参考，检索失败不影响出题
    try:
        hits = search(_resume_text(resume) + " " + _req_text(reqs), job, 5)
        if hits:
            prompt += "\n\n参考题库（可改写，也可不用）：\n"
            prompt += "\n".join(f"- {h['stem']}" for h in hits)
    except Exception:
        pass

    data, usage = chat_json([{"role": "user", "content": prompt}], temperature=0.7)

    return {
        "type": "new_question",
        "stem": (data.get("stem") or "").strip(),
        "basedOn": (data.get("basedOn") or "").strip(),
        "dimension": (data.get("dimension") or "技术深度").strip(),
        "usage": {"tokensIn": usage.tokens_in,
                  "tokensOut": usage.tokens_out,
                  "cost": round(usage.cost, 6)},
    }


def _has_detail(answer: str) -> bool:
    import re
    if re.search(r"\d", answer):
        return True
    return any(kw in answer for kw in ("因为", "所以", "当时", "比如", "具体来说", "我们"))


def should_follow_up(answer: str, depth: int, max_depth: int) -> bool:
    if depth >= max_depth:
        return False
    if len(answer.strip()) < MIN_LEN:
        return True
    return True     # 有细节也给一次追问机会，模拟真实压力


def _cites(follow: str, answer: str) -> bool:
    """追问必须包含回答里的原话片段，否则视为套话。

    阈值按回答长度自适应：短回答（<20 字）用 2 个字，
    否则像「缓存」这种两字术语永远判不过，会误杀正常追问。
    """
    answer = answer.strip()
    if not answer:
        return False

    min_len = 2 if len(answer) < 20 else 3
    for i in range(len(answer) - min_len + 1):
        frag = answer[i:i + min_len].strip()
        if frag and frag in follow:
            return True
    return False


def follow_up(job: str, question: str, answer: str) -> dict:
    prompt = fill(load("question_follow"),
                  {"job": job, "question": question, "answer": answer})

    data, usage = chat_json([{"role": "user", "content": prompt}], temperature=0.7)
    text = (data.get("followUp") or "").strip()

    if text and not _cites(text, answer):
        text = ""      # 套话，丢弃

    return {
        "type": "follow_up" if text else "need_new",
        "stem": text,
        "basedOn": "",
        "dimension": "技术深度",
        "usage": {"tokensIn": usage.tokens_in,
                  "tokensOut": usage.tokens_out,
                  "cost": round(usage.cost, 6)},
    }
