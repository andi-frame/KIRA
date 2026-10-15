from pydantic_settings import BaseSettings, SettingsConfigDict

DEFAULT_JWT_SECRET = "dev-only-change-me-please-use-a-long-random-secret"
MIN_SECRET_LENGTH = 32


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=("../.env", ".env"), extra="ignore")

    environment: str = "development"  # production menolak kunci JWT bawaan
    database_url: str = "postgresql+asyncpg://kira:kira@localhost:5455/kira"
    test_database_url: str = "postgresql+asyncpg://kira:kira@localhost:5455/kira_test"
    jwt_secret: str = DEFAULT_JWT_SECRET
    jwt_expire_minutes: int = 60  # token akses singkat; perangkat memperbaruinya dengan token penyegar
    refresh_expire_days: int = 30
    anthropic_api_key: str = ""
    llm_model_chat: str = "claude-sonnet-5-5"
    llm_model_extract: str = "claude-haiku-5-5"
    stt_base_url: str = "https://api.groq.com/openai/v1"
    stt_api_key: str = ""
    stt_model: str = "whisper-large-v3-turbo"
    demo_cache: bool = False
    # Origin yang boleh memanggil API dari browser (Flutter web). Pisahkan dengan koma; '*' untuk demo.
    cors_origins: str = "*"
    # Rahasia bersama dengan bot WhatsApp (Baileys, prototype). Kosong = kanal WhatsApp nonaktif.
    bot_secret: str = ""
    scheduler_enabled: bool = True
    # Alamat publik API, dipakai membentuk tautan ringkasan untuk dokter (mis. https://api.kira.example).
    public_base_url: str = "http://localhost:8000"


def validate_settings(s: Settings) -> None:
    """Gagal cepat bila konfigurasi tidak aman untuk produksi (token bisa dipalsukan dengan kunci publik)."""
    if s.environment.lower() != "production":
        return
    if s.jwt_secret == DEFAULT_JWT_SECRET or len(s.jwt_secret) < MIN_SECRET_LENGTH:
        raise RuntimeError(
            "JWT_SECRET harus diganti dengan string acak minimal 32 karakter saat ENVIRONMENT=production."
        )


settings = Settings()
