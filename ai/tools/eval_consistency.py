"""评分一致性评测：同一份回答跑多轮，看分数稳不稳。

用法：
    cd ai
    python tools/eval_consistency.py                     # 默认配置（读环境变量）
    python tools/eval_consistency.py --rounds 3 --dim 技术深度

    对比实验（Day 20 五步法）：
    $env:SCORE_KEYPOINTS="0"; $env:SCORE_DOUBLE="0"; python tools/eval_consistency.py
    $env:SCORE_KEYPOINTS="1"; $env:SCORE_DOUBLE="0"; python tools/eval_consistency.py
    $env:SCORE_KEYPOINTS="1"; $env:SCORE_DOUBLE="1"; python tools/eval_consistency.py

指标：
    差值不超过 1 分的比例 = 同一题多次评分里 max-min <= 1 的题目占比（越高越稳）
    与人工平均差         = 多次评分均值与人工标注分的平均绝对差
"""

import argparse
import json
import statistics
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from app.services import scorer  # noqa: E402
from app.services.scorer import score_answer  # noqa: E402

CASE_FILE = ROOT / "data" / "eval" / "answers.json"


def run(dim: str = "技术深度", rounds: int = 3, pause: float = 0.0) -> dict:
    cases = json.loads(CASE_FILE.read_text(encoding="utf-8"))
    rows = []

    for c in cases:
        scores = []
        for _ in range(rounds):
            r = score_answer(c["question"], c["answer"], [dim])
            scores.append(r["dimensions"][0]["score"])
            if pause:
                time.sleep(pause)

        rows.append({
            "id": c["id"],
            "scores": scores,
            "diff": max(scores) - min(scores),
            "mean": statistics.mean(scores),
            "human": c["humanScore"],
        })
        print(f"{c['id']}  运行 {scores}  差值 {rows[-1]['diff']}  人工 {c['humanScore']}")

    within_one = sum(1 for r in rows if r["diff"] <= 1) / len(rows)
    avg_gap = statistics.mean(abs(r["mean"] - r["human"]) for r in rows)
    max_diff = max(r["diff"] for r in rows)

    config = f"关键点={'开' if scorer.USE_KEYPOINTS else '关'} 双次={'开' if scorer.USE_DOUBLE else '关'} 证据={'开' if scorer.USE_EVIDENCE else '关'}"
    print()
    print(f"配置              : {config}")
    print(f"样本数            : {len(rows)}")
    print(f"差值不超过 1 分的比例 : {within_one:.0%}")
    print(f"最大差值          : {max_diff}")
    print(f"与人工平均差       : {avg_gap:.2f} 分")

    return {
        "config": config,
        "samples": len(rows),
        "within_one": round(within_one, 4),
        "max_diff": max_diff,
        "avg_gap": round(avg_gap, 2),
        "rows": rows,
    }


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--dim", default="技术深度")
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--pause", type=float, default=0.0, help="每次调用之间停几秒，防限流")
    ap.add_argument("--json", default="", help="把结果写到这个文件")
    args = ap.parse_args()

    result = run(args.dim, args.rounds, args.pause)
    if args.json:
        Path(args.json).write_text(
            json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"结果已写入 {args.json}")
