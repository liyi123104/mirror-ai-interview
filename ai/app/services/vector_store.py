import threading

from app.services.embed import embed
from app.services.similarity import cosine

_lock = threading.Lock()
_vectors: dict[str, list[float]] = {}
_meta: dict[str, dict] = {}


def index(items: list[dict]) -> dict:
    """items: [{"id","stem","job","dimension"}]"""
    if not items:
        return {"indexed": 0, "failed": 0}

    texts = [f"{it['stem']} 维度：{it.get('dimension', '')}" for it in items]

    try:
        vectors = embed(texts)
    except Exception:
        return {"indexed": 0, "failed": len(items)}

    with _lock:
        for it, vec in zip(items, vectors):
            _vectors[it["id"]] = vec
            _meta[it["id"]] = it

    return {"indexed": len(items), "failed": 0}


def remove(qid: str) -> None:
    with _lock:
        _vectors.pop(qid, None)
        _meta.pop(qid, None)


def search(query: str, job: str | None, top_k: int) -> list[dict]:
    if not _vectors:
        return []

    qvec = embed([query])[0]

    with _lock:
        scored = []
        for qid, vec in _vectors.items():
            m = _meta[qid]
            if job and m.get("job") != job:
                continue
            scored.append({**m, "score": round(cosine(qvec, vec), 4)})

    scored.sort(key=lambda x: x["score"], reverse=True)
    return scored[:top_k]


def size() -> int:
    return len(_vectors)
