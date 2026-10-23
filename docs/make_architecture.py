"""生成 docs/architecture.png。

用法（用带 Pillow 的 Python 跑）：
    python docs/make_architecture.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1080, 660
FONT_PATH = "C:/Windows/Fonts/msyh.ttc"

BG = (247, 248, 250)
BOX = (255, 255, 255)
EDGE = (208, 215, 222)
TEXT = (31, 35, 40)
MUTED = (110, 119, 129)
ACCENT = (64, 158, 255)
WARN = (230, 145, 56)

FONT_TITLE = ImageFont.truetype(FONT_PATH, 22)
FONT_BOX = ImageFont.truetype(FONT_PATH, 18)
FONT_SMALL = ImageFont.truetype(FONT_PATH, 15)


def box(draw, xy, title, sub="", fill=BOX, border=EDGE):
    x1, y1, x2, y2 = xy
    draw.rounded_rectangle(xy, radius=10, fill=fill, outline=border, width=2)
    tw = draw.textlength(title, font=FONT_BOX)
    draw.text(((x1 + x2 - tw) / 2, y1 + 14), title, font=FONT_BOX, fill=TEXT)
    if sub:
        sw = draw.textlength(sub, font=FONT_SMALL)
        draw.text(((x1 + x2 - sw) / 2, y1 + 46), sub, font=FONT_SMALL, fill=MUTED)


def arrow(draw, start, end, label="", color=ACCENT, dash=False):
    draw.line([start, end], fill=color, width=2 if not dash else 2)
    # 箭头
    x1, y1 = start
    x2, y2 = end
    dx, dy = x2 - x1, y2 - y1
    length = max((dx * dx + dy * dy) ** 0.5, 1)
    ux, uy = dx / length, dy / length
    px, py = -uy, ux
    tip = (x2, y2)
    left = (x2 - ux * 12 + px * 6, y2 - uy * 12 + py * 6)
    right = (x2 - ux * 12 - px * 6, y2 - uy * 12 - py * 6)
    draw.polygon([tip, left, right], fill=color)

    if label:
        mx, my = (x1 + x2) / 2, (y1 + y2) / 2 - 14
        tw = draw.textlength(label, font=FONT_SMALL)
        draw.rectangle([mx - tw / 2 - 4, my - 11, mx + tw / 2 + 4, my + 11], fill=BG)
        draw.text((mx - tw / 2, my - 8), label, font=FONT_SMALL, fill=MUTED)


def main():
    img = Image.new("RGB", (WIDTH, HEIGHT), BG)
    d = ImageDraw.Draw(img)

    d.text((40, 24), "面镜 · 一次面试请求怎么走完全程", font=FONT_TITLE, fill=TEXT)

    # 第一层
    box(d, (60, 90, 250, 170), "浏览器", "Vue3 + Nginx 反代")
    box(d, (330, 90, 560, 170), "Nginx :80", "静态资源 / try_files 回落")

    # 第二层
    box(d, (280, 250, 560, 350), "Spring Boot :8080", "JWT 鉴权 · 状态机 · 题库 · 报告")
    box(d, (120, 420, 330, 500), "MySQL 8", "6 张表 · turn/report/cost_log")

    # 第三层
    box(d, (700, 250, 1010, 350), "FastAPI :8000", "PDF 解析 · 向量检索 · 出题/评分/复盘")
    box(d, (700, 420, 850, 500), "DeepSeek", "出题 · 评分 · 复盘")
    box(d, (880, 420, 1030, 500), "Ollama", "bge-m3 向量")

    # 箭头
    arrow(d, (250, 130), (330, 130), "① 打开页面")
    arrow(d, (445, 170), (445, 250), "② /api/**")
    arrow(d, (330, 350), (330, 420), "JDBC")
    arrow(d, (560, 300), (700, 300), "内部 HTTP + Token", color=WARN)
    arrow(d, (775, 350), (775, 420), "调用")
    arrow(d, (955, 350), (955, 420), "embed")

    d.text((700, 205), "AI 服务不对外开放", font=FONT_SMALL, fill=WARN)
    d.text((40, 560), "③ 回答后：Java 调 /ai/score 四维双评 → 写 turn.dimensions_json 与 cost_log", font=FONT_SMALL, fill=MUTED)
    d.text((40, 588), "④ 结束后：Java 并发生成逐题复盘 → report 落库（session_id 唯一，幂等）", font=FONT_SMALL, fill=MUTED)
    d.text((40, 616), "⑤ 任何一步 Python 不可用：AiClient 抛 AiUnavailableException → 全局异常处理器统一返回 5030", font=FONT_SMALL, fill=MUTED)

    out = Path(__file__).resolve().parent / "architecture.png"
    img.save(out)
    print(f"写入 {out}")


if __name__ == "__main__":
    main()
