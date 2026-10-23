import io

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile

from app.common import ok, verify_token
from app.services.parser import extract_text
from app.services.resume_rules import (
    extract_basic,
    extract_skills,
    guess_name,
    split_sections,
)

router = APIRouter(prefix="/ai/resume", dependencies=[Depends(verify_token)])

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

    return ok({
        "name": guess_name(sections, text),
        "phone": basic["phone"],
        "email": basic["email"],
        "education": "",
        "projects": [],
        "skills": skills,
        "needsReview": not skills,
        "rawText": text,
        "usage": ZERO_USAGE,
    })
