import io
import logging
import re

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.common import ok, verify_token
from app.config import settings
from app.services.parser import extract_text
from app.services.resume_ai import extract_by_llm
from app.services.resume_rules import (
    extract_basic,
    extract_skills,
    guess_name,
    split_sections,
)

router = APIRouter(prefix="/ai/resume", dependencies=[Depends(verify_token)])
log = logging.getLogger("mirror.resume")

ZERO_USAGE = {"tokensIn": 0, "tokensOut": 0, "cost": 0.0}


@router.post("/parse")
async def parse(file: UploadFile = File(...)):
    if not (file.filename or "").lower().endswith(".pdf"):
        raise HTTPException(400, "只支持 PDF 文件")

    content = await file.read()
    if len(content) > 10 * 1024 * 1024:
        raise HTTPException(400, "文件不能超过 10MB")

    try:
        text = extract_text(io.BytesIO(content))
    except Exception:
        raise HTTPException(400, "PDF 读取失败，文件可能损坏")

    if len(text.strip()) < 100:
        raise HTTPException(400, "这份 PDF 没有文字层，可能是扫描件，请换电子版")

    sections = split_sections(text)
    basic = extract_basic(text)
    skills = extract_skills(sections)
    name = guess_name(sections, text)

    education, projects = "", []
    needs_review = False
    usage = ZERO_USAGE
    extra: dict = {}

    # 规则只能抽技能，学历和项目得靠模型补。
    # 想省 token 就把 .env 里的 RESUME_LLM_ENRICH 设成 false，只走规则。
    if settings.resume_llm_enrich and (not skills or not projects):
        try:
            extra = extract_by_llm(text)
            merged = list(skills)
            for s in extra.get("skills") or []:
                s = (s or "").strip()
                if s and s not in merged:
                    merged.append(s)
            # 「MVC」和「MVC 架构」这种包含关系，留更“纯技术名”的那个：
            # 中文字越少越好，同等情况留更长的（Spring Boot 胜过 Spring）
            def better(a: str, b: str) -> bool:
                cjk_a = len(re.findall(r"[\u4e00-\u9fa5]", a))
                cjk_b = len(re.findall(r"[\u4e00-\u9fa5]", b))
                return (cjk_a, -len(a)) < (cjk_b, -len(b))

            skills = [s for s in merged
                      if not any(s != o and s in o and better(o, s) for o in merged)]
            education = (extra.get("education") or "").strip()
            projects = extra.get("projects") or []
            usage = extra.get("usage", ZERO_USAGE)
        except Exception as e:
            log.warning("简历兜底抽取失败：%s", e)
            needs_review = True

    # 姓名规则没拿到时，可以借模型的结果
    if not name:
        name = (extra.get("name") or "").strip()

    if not skills:
        needs_review = True

    return ok({
        "name": name,
        "phone": basic["phone"],
        "email": basic["email"],
        "education": education,
        "projects": projects,
        "skills": skills,
        "needsReview": needs_review,
        "rawText": text,
        "usage": usage,
    })
