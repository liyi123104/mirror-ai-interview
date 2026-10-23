from fastapi import FastAPI

from app.routers import resume, stub

app = FastAPI(title="面镜 AI 服务", version="0.2.0")
app.include_router(stub.router)
app.include_router(resume.router)


@app.get("/ai/health")
def health():
    return {"status": "ok", "service": "ai", "version": "0.2.0"}
