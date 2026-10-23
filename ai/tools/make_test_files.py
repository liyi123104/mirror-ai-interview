"""生成测试用的简历 PDF（只在开发时跑一次，生成的文件进仓库）。

依赖：pip install reportlab（仅测试用，不进 requirements.txt）
用法：
    cd ai
    python tools/make_test_files.py
"""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "tests" / "data"
OUT.mkdir(parents=True, exist_ok=True)

FONT_CANDIDATES = [
    ("C:/Windows/Fonts/msyh.ttc", 0),
    ("C:/Windows/Fonts/simsun.ttc", 0),
    ("C:/Windows/Fonts/simhei.ttf", None),
]


def build_resume_pdf() -> None:
    from reportlab.lib.pagesizes import A4
    from reportlab.pdfbase import pdfmetrics
    from reportlab.pdfbase.ttfonts import TTFont
    from reportlab.pdfgen import canvas

    font_name = None
    for path, index in FONT_CANDIDATES:
        if not Path(path).exists():
            continue
        try:
            if index is None:
                pdfmetrics.registerFont(TTFont("CN", path))
            else:
                pdfmetrics.registerFont(TTFont("CN", path, subfontIndex=index))
            font_name = "CN"
            break
        except Exception:
            continue

    if font_name is None:
        raise SystemExit("系统里找不到中文字体，换一台机器再生成")

    lines = [
        "张三",
        "求职意向：Java 后端开发",
        "个人信息",
        "📞 13800138000",
        "✉ zhangsan@example.com",
        "📍 辽宁省锦州市",
        "教育背景",
        "某某大学 | 软件工程 | 本科 2021.09 - 2025.07",
        "专业技能",
        "· 后端开发：掌握 Java、Spring Boot，理解 MVC 架构与 REST 设计",
        "· 数据库：熟悉 MySQL 表结构设计与索引优化，了解 Redis 缓存",
        "· 工具：熟练使用 Maven、Git、IntelliJ IDEA、Navicat",
        "· 系统：熟悉 Linux 常用命令，能用 Docker 部署服务",
        "项目经历",
        "面镜 · AI 模拟面试系统 2025.03 - 2025.06",
        "· 负责 Java 侧业务与状态机，Python 侧提供出题与评分能力",
        "· 用 Redis 做会话缓存，把接口 P95 从 800ms 降到 120ms",
    ]

    pdf_path = OUT / "sample-resume.pdf"
    c = canvas.Canvas(str(pdf_path), pagesize=A4)
    c.setFont(font_name, 11)
    y = 800
    for line in lines:
        c.drawString(50, y, line)
        y -= 22
    c.showPage()
    c.save()
    print(f"写入 {pdf_path}")


def build_blank_pdf() -> None:
    """没有文字层的 PDF，用来模拟扫描件。"""
    from pypdf import PdfWriter

    writer = PdfWriter()
    writer.add_blank_page(width=595, height=842)
    path = OUT / "blank.pdf"
    with open(path, "wb") as f:
        writer.write(f)
    print(f"写入 {path}")


def build_fake_docx() -> None:
    path = OUT / "fake.docx"
    path.write_bytes(b"PK\x03\x04 fake docx, only for extension check")
    print(f"写入 {path}")


def build_english_pdf() -> None:
    """格式不标准（全英文）的简历：规则抽不到技能，用来测模型兜底。"""
    from reportlab.lib.pagesizes import A4
    from reportlab.pdfgen import canvas

    lines = [
        "ZHANG SAN",
        "Backend Engineer / Java",
        "Contact: +86 13900139000  zhang.san@example.com",
        "",
        "SUMMARY",
        "Four years building payment services. Care about correctness and latency.",
        "",
        "EXPERIENCE",
        "Mirror Tech 2023 - now, backend engineer",
        "- Built an interview service on Spring Boot and MySQL",
        "- Cut P95 latency from 800ms to 120ms with Redis caching",
        "",
        "SKILLS",
        "Java, Spring Boot, MySQL, Redis, Linux, Docker, Maven",
        "",
        "EDUCATION",
        "Some University, Software Engineering, Bachelor 2021 - 2025",
    ]

    path = OUT / "sample-resume-en.pdf"
    c = canvas.Canvas(str(path), pagesize=A4)
    c.setFont("Helvetica", 11)
    y = 800
    for line in lines:
        c.drawString(50, y, line)
        y -= 22
    c.showPage()
    c.save()
    print(f"写入 {path}")


if __name__ == "__main__":
    build_resume_pdf()
    build_english_pdf()
    build_blank_pdf()
    build_fake_docx()
    print("测试文件生成完成")
