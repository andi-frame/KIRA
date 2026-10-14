from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=("../.env", ".env"), extra="ignore")

    database_url: str = "postgresql+asyncpg://kira:kira@localhost:5455/kira"
    test_database_url: str = "postgresql+asyncpg://kira:kira@localhost:5455/kira_test"
    jwt_secret: str = "dev-only-change-me-please-use-a-long-random-secret"
    jwt_expire_minutes: int = 720
    anthropic_api_key: str = ""
    llm_model_chat: str = "claude-sonnet-5-5"
    llm_model_extract: str = "claude-haiku-5-5"
    stt_base_url: str = "https://api.groq.com/openai/v1"
    stt_api_key: str = ""
    stt_model: str = "whisper-large-v3-turbo"
    demo_cache: bool = False


settings = Settings()
