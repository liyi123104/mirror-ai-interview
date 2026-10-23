from fastapi import FastAPI

from app.routers import interview, jd, question, resume

app = FastAPI(title="面镜 AI 服务", version="0.3.0")

app.include_router(resume.router)
app.include_router(jd.router)
app.include_router(question.router)
app.include_router(interview.router)


@app.get("/ai/health")
def health():
    return {"status": "ok", "service": "ai", "version": "0.3.0"}
