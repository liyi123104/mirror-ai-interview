"""追问规则的单元测试（不调模型，跑得很快）。

用法：
    cd ai
    python -m unittest tests.test_interviewer -v
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.services.interviewer import MIN_LEN, _cites, should_follow_up


class CitesTest(unittest.TestCase):
    def test_引用了原话里的技术名词(self):
        answer = "我用 Redis 做缓存，因为读多写少"
        follow = "为什么选 Redis 而不是本地缓存？"
        self.assertTrue(_cites(follow, answer))

    def test_短回答用两个字也能过(self):
        answer = "做缓存"
        follow = "缓存击穿怎么处理？"
        self.assertTrue(_cites(follow, answer))

    def test_套话要被丢掉(self):
        answer = "我用 Redis 做缓存，因为读多写少"
        follow = "你能详细说说吗？"
        self.assertFalse(_cites(follow, answer))

    def test_空回答不算引用(self):
        self.assertFalse(_cites("随便问问", ""))


class ShouldFollowUpTest(unittest.TestCase):
    def test_短回答要追问(self):
        self.assertTrue(should_follow_up("用 Redis", 0, 2))

    def test_到达最大深度不再追问(self):
        self.assertFalse(should_follow_up("用 Redis", 2, 2))

    def test_长回答也给一次压力追问(self):
        self.assertTrue(should_follow_up("x" * (MIN_LEN + 10), 1, 2))


if __name__ == "__main__":
    unittest.main()
