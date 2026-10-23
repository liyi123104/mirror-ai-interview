import re

SECTION_NAMES = ["个人信息", "教育", "实习", "工作", "项目", "技能", "证书", "自我评价"]

# 中文简历里常见的英文/别名写法，映射到同一节
SECTION_ALIASES = {
    "基本信息": "个人信息",
    "联系方式": "个人信息",
    "教育背景": "教育",
    "教育经历": "教育",
    "实习经历": "实习",
    "实训经历": "实习",
    "工作经历": "工作",
    "项目经历": "项目",
    "项目经验": "项目",
    "专业技能": "技能",
    "技能特长": "技能",
    "获奖情况": "证书",
    "荣誉证书": "证书",
}

# 常见技术词，命中就直接当技能。简历里的技能常常夹在句子里，靠这个兜底。
TECH_WORDS = [
    "Java", "Spring Boot", "Spring Cloud", "Spring", "MyBatis", "JVM", "Python",
    "C++", "C语言", "C", "Go", "JavaScript", "TypeScript", "Vue", "React", "Node.js",
    "MySQL", "PostgreSQL", "Oracle", "Redis", "MongoDB", "Elasticsearch", "SQL",
    "Linux", "Docker", "Kubernetes", "K8s", "Nginx", "Tomcat", "Maven", "Gradle",
    "Git", "SVN", "Navicat", "IntelliJ IDEA", "IDEA", "VS Code", "Postman",
    "MVC", "HTTP", "TCP", "REST", "FastAPI", "Django", "Flask", "Ollama",
    "HTML", "CSS", "jQuery", "Bootstrap", "Element UI", "Element Plus",
]

# 这些词出现说明是描述句，不是技能名
SENTENCE_MARKERS = ("的", "了", "并", "且", "能", "可", "会", "擅长", "理解", "掌握", "具备", "熟悉", "了解", "使用", "完成", "负责")


def _match_section(line: str) -> str | None:
    for alias, name in SECTION_ALIASES.items():
        if len(line) <= 12 and alias in line:
            return name
    return next((n for n in SECTION_NAMES if len(line) <= 12 and n in line), None)


def split_sections(text: str) -> dict[str, str]:
    """按标题把简历切成若干段。"""
    result: dict[str, str] = {}
    current = "其他"
    buffer: list[str] = []

    for line in text.splitlines():
        s = line.strip()
        if not s:
            continue

        hit = _match_section(s)
        if hit:
            if buffer:
                result[current] = "\n".join(buffer)
            current, buffer = hit, []
        else:
            buffer.append(s)

    if buffer:
        result[current] = "\n".join(buffer)
    return {k: v for k, v in result.items() if v.strip()}


def extract_basic(text: str) -> dict:
    phone = re.search(r"1[3-9]\d{9}", text)
    email = re.search(r"[\w.-]+@[\w.-]+\.\w+", text)
    return {
        "phone": phone.group() if phone else "",
        "email": email.group() if email else "",
    }


def _clean_bullet(line: str) -> str:
    """去掉行首的项目符号，以及「技术基础：」这类小标题。"""
    s = line.strip().lstrip("·•◦-—*|►▸ ")
    if "：" in s:
        s = s.split("：", 1)[1]
    elif ":" in s:
        s = s.split(":", 1)[1]
    return s.strip()


def _norm(item: str) -> str:
    """去掉首尾符号，把「C 语言」这种被 PDF 拆开的词合回去。"""
    item = item.strip(" 。.：:、,，;；|/-—•")
    item = re.sub(r"\s+", " ", item)
    item = re.sub(r"(?<=[A-Za-z])\s+(?=[\u4e00-\u9fa5])", "", item)
    return item.strip()


def _looks_like_skill(s: str) -> bool:
    if not (1 < len(s) <= 24):
        return False
    # 技能名至少带一个拉丁字母：纯中文碎片大多是 PDF 断行断出来的句子残渣
    if not re.search(r"[A-Za-z]", s):
        return False
    return not any(m in s for m in SENTENCE_MARKERS)


def extract_skills(sections: dict[str, str]) -> list[str]:
    """技能优先按行拆，拆不出来的碎片丢掉，最后用技术词典兜底补全。"""
    text = sections.get("技能", "")
    # PDF 常把「C 语言」拆成两个字符，这里先铺平一份给词典用
    flat = re.sub(r"(?<=[A-Za-z])\s+(?=[\u4e00-\u9fa5])", "", text)

    skills: list[str] = []
    seen: set[str] = set()

    def add(item: str) -> None:
        item = _norm(item)
        if item and item not in seen and _looks_like_skill(item):
            seen.add(item)
            skills.append(item)

    for line in text.splitlines():
        body = _clean_bullet(line)
        if not body:
            continue
        for part in re.split(r"[、,，；;|/]+|\s{2,}", body):
            add(part)

    # 句子型技能描述（“掌握 Java、Spring Boot …”）：用技术词典把词捞出来
    for word in sorted(TECH_WORDS, key=len, reverse=True):
        if word in seen:
            continue
        # 词边界，避免 Java 命中 JavaScript、C 命中 CSS
        pattern = rf"(?<![A-Za-z+#.]){re.escape(word)}(?![A-Za-z+#])"
        if not (re.search(pattern, text) or re.search(pattern, flat)):
            continue
        # 被更长的技能覆盖的短词就不重复加了（Spring 之于 Spring Boot）
        if any(word != s and word in s for s in skills):
            continue
        seen.add(word)
        skills.append(word)

    return skills


def guess_name(sections: dict[str, str], text: str) -> str:
    """姓名：先看顶部几行，再退回「个人信息」段。"""
    candidates = [ln.strip() for ln in text.splitlines() if ln.strip()][:6]
    candidates += [ln.strip() for ln in sections.get("个人信息", "").splitlines() if ln.strip()]

    for line in candidates:
        compact = re.sub(r"\s+", "", line)
        if re.fullmatch(r"[\u4e00-\u9fa5]{2,4}", compact):
            return compact
    return ""
