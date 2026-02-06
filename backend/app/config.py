"""Application configuration loaded from environment variables."""

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """LinkLess API settings."""

    # App
    app_name: str = "LinkLess"
    debug: bool = False
    secret_key: str = "change-me-in-production"
    allowed_origins: list[str] = ["*"]

    # Database
    database_url: str = "sqlite+aiosqlite:///./linkless.db"

    # JWT
    jwt_algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24  # 24 hours
    refresh_token_expire_days: int = 30

    # AI Providers — set the ones you want to use
    ai_provider: str = "openai"  # openai | anthropic | google | xai

    # OpenAI (Whisper for transcription, GPT for summarization)
    openai_api_key: str = ""

    # Anthropic (Claude for summarization and analysis)
    anthropic_api_key: str = ""

    # Google (Gemini for transcription and summarization)
    google_api_key: str = ""

    # xAI (Grok for summarization)
    xai_api_key: str = ""

    # Storage
    upload_dir: str = "./uploads"
    max_audio_file_size_mb: int = 50

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


settings = Settings()
