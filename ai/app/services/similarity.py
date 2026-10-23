def cosine(a: list[float], b: list[float]) -> float:
    """余弦相似度：两个向量方向有多接近，结果在 -1 到 1 之间。

    做法：
    1. 对应位置的数相乘，再全部加起来（重叠程度）
    2. 各自平方求和再开根号（各自的长度）
    3. 重叠程度除以两个长度的乘积
    """
    if not a or not b or len(a) != len(b):
        return 0.0

    dot = 0.0
    for x, y in zip(a, b):
        dot += x * y

    na = sum(x * x for x in a) ** 0.5
    nb = sum(y * y for y in b) ** 0.5

    if na == 0 or nb == 0:
        return 0.0

    return dot / (na * nb)
