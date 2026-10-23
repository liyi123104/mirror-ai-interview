"""验证证据校验能不能拦住编造的依据。

用法：
    cd ai
    python tools/try_evidence.py
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.services.scorer import score_once, validate_evidence

CASES = [
    ("讲讲 Redis 缓存穿透", "我用布隆过滤器挡住了不存在的 key，另外把空结果也缓存起来。"),
    ("讲讲你的项目", "不知道"),
    ("讲讲并发", "我们系统 QPS 五千，用了线程池和限流，压测过三轮。"),
]

if __name__ == "__main__":
    passed = 0
    for q, a in CASES:
        r = score_once(q, a, "技术深度")
        ok = validate_evidence(r["evidence"], a)
        passed += 1 if ok else 0
        print(f"回答长度 {len(a):>3} | 分数 {r['score']} | 证据校验 {'通过' if ok else '失败'}")
        print(f"  证据：{r['evidence'][:40]}")
    print(f"\n{passed}/{len(CASES)} 条通过")
