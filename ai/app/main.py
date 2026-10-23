from fastapi import FastAPI

from app.routers import stub

app = FastAPI(title="面镜 AI 服务", version="0.1.0")
app.include_router(stub.router)


@app.get("/ai/health")
def health():
    return {"status": "ok", "service": "ai"}