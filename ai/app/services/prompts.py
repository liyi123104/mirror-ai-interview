from pathlib import Path

PROMPT_DIR = Path(__file__).resolve().parent.parent.parent / "prompts"

_cache: dict[str, str] = {}


def load(name: str) -> str:
    if name not in _cache:
        path = PROMPT_DIR / f"{name}.txt"
        if not path.exists():
            raise FileNotFoundError(f"提示词不存在：{path}")
        _cache[name] = path.read_text(encoding="utf-8")
    return _cache[name]


def fill(template: str, values: dict[str, str]) -> str:
    result = template
    for k, v in values.items():
        result = result.replace("{{" + k + "}}", str(v))
    return result