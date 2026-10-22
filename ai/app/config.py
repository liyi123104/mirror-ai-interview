from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    deepseek_api_key: str = ""
    deepseek_base_url: str = "https://api.deepseek.com"
    model_main: str = "deepseek-chat"

    ollama_base_url: str = "http://127.0.0.1:11434/v1"
    model_fallback: str = "qwen2.5:7b"
    embed_model: str = "bge-m3"

    internal_token: str = "dev-token-change-me"
    request_timeout: int = 60


settings = Settings()