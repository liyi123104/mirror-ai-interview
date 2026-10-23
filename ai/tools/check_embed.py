"""验证 bge-m3 向量化是否正常。

用法：
    cd ai
    python tools/check_embed.py

验收标准（Day 13）：
1. 维度是 1024
2. 同义句相似度大于 0.7
3. 无关句相似度小于 0.5
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.services.embed import embed
from app.services.similarity import cosine

PAIRS = [
    ("同理句", "Redis 缓存穿透怎么解决", "如何应对缓存穿透问题"),
    ("同理句", "说说 MySQL 索引失效的场景", "哪些情况下 MySQL 的索引会用不上"),
    ("同理句", "Java 里 HashMap 是怎么实现的", "HashMap 的底层数据结构是什么"),
    ("无关句", "元组是不可变的，列表是可变的", "今天天气不错，想出去走走"),
]


def main():
    texts = []
    for _, a, b in PAIRS:
        texts.extend([a, b])

    vectors = embed(texts)
    dim = len(vectors[0])

    print(f"维度：{dim}")
    print("-" * 48)
    scores = []
    for i, (kind, a, b) in enumerate(PAIRS):
        score = cosine(vectors[i * 2], vectors[i * 2 + 1])
        scores.append((kind, score))
        print(f"{kind}  {score:.3f}  {a} <> {b}")

    same = [s for k, s in scores if k == "同理句"]
    diff = [s for k, s in scores if k == "无关句"]

    ok = (dim == 1024
          and all(s > 0.7 for s in same)
          and all(s < 0.5 for s in diff))

    print("-" * 48)
    print(f"最小同义相似度 {min(same):.3f}（要求 > 0.7），最大无关相似度 {max(diff):.3f}（要求 < 0.5）")
    print("结论：" + ("通过" if ok else "不通过，先修好再往下"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
