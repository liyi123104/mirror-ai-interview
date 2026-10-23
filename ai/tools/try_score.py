"""手动试一次评分。

用法：
    cd ai
    python tools/try_score.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.services.scorer import score_once


if __name__ == "__main__":
    q = "讲讲 Redis 缓存穿透怎么处理"
    a = "用布隆过滤器挡住不存在的 key，还可以把空结果也缓存起来，设一个短过期时间。"
    r = score_once(q, a, "技术深度")
    print(f"分数：{r['score']}")
    print(f"理由：{r['reason']}")
    print(f"证据：{r['evidence']}")
