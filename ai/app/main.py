from fastapi import FastAPI

app = FastAPI(title="面镜 AI 服务", version="0.1.0")


@app.get("/ai/health")
def health():
    return {"status": "ok", "service": "ai"}