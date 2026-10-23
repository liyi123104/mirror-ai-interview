from openai import OpenAI

from app.config import settings

_client = OpenAI(base_url=settings.ollama_base_url, api_key="ollama")


def embed(texts: list[str]) -> list[list[float]]:
    """批量向量化。一次最多 16 条，太多有些服务会拒绝。"""
    if not texts:
        return []

    result: list[list[float]] = []
    for i in range(0, len(texts), 16):
        batch = texts[i:i + 16]
        resp = _client.embeddings.create(model=settings.embed_model, input=batch)
        result.extend(d.embedding for d in resp.data)
    return result
