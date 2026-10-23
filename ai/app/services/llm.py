import json
import time
from dataclasses import dataclass

from openai import OpenAI

from app.config import settings


@dataclass
class LlmResult:
    text: str
    tokens_in: int
    tokens_out: int
    cost: float
    latency_ms: int
    model: str


PRICE_IN = 2.0
PRICE_OUT = 8.0


def _client(primary: bool):
    if primary:
        return OpenAI(base_url=settings.deepseek_base_url,
                      api_key=settings.deepseek_api_key), settings.model_main
    return OpenAI(base_url=settings.ollama_base_url,
                  api_key="ollama"), settings.model_fallback


def chat(messages: list[dict], temperature: float = 0.3,
         json_mode: bool = False, max_tokens: int = 1024) -> LlmResult:
    last_err = None

    for primary in (True, False):
        client, model = _client(primary)
        start = time.time()
        try:
            kwargs = dict(model=model, messages=messages,
                          temperature=temperature, max_tokens=max_tokens)
            if json_mode:
                kwargs["response_format"] = {"type": "json_object"}

            resp = client.chat.completions.create(
                timeout=settings.request_timeout, **kwargs)

            usage = resp.usage
            cost = (usage.prompt_tokens * PRICE_IN
                    + usage.completion_tokens * PRICE_OUT) / 1_000_000

            return LlmResult(
                text=resp.choices[0].message.content or "",
                tokens_in=usage.prompt_tokens,
                tokens_out=usage.completion_tokens,
                cost=cost,
                latency_ms=int((time.time() - start) * 1000),
                model=model,
            )
        except Exception as e:
            last_err = e
            continue

    raise RuntimeError(f"模型调用失败：{last_err}")


def chat_json(messages: list[dict], temperature: float = 0.0):
    result = chat(messages, temperature=temperature, json_mode=True)
    text = result.text.strip()

    if text.startswith("```"):
        text = text.strip("`")
        if text.lower().startswith("json"):
            text = text[4:]

    try:
        return json.loads(text), result
    except json.JSONDecodeError:
        s, e = text.find("{"), text.rfind("}") + 1
        if s >= 0 and e > s:
            return json.loads(text[s:e]), result
        raise ValueError(f"模型没有返回合法 JSON：{text[:200]}")