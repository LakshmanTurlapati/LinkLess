from functools import lru_cache

from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Database
    database_url: str = (
        "postgresql+asyncpg://linkless:linkless@localhost:5432/linkless"
    )

    # Redis
    redis_url: str = "redis://localhost:6379"

    # Tigris Object Storage
    tigris_endpoint: str = "https://t3.storage.dev"
    tigris_bucket: str = "linkless-audio"
    aws_access_key_id: str = ""
    aws_secret_access_key: str = ""

    # JWT
    jwt_secret_key: str = ""
    access_token_expire_minutes: int = 30
    refresh_token_expire_days: int = 30

    # Twilio Verify
    twilio_account_sid: str = ""
    twilio_auth_token: str = ""
    twilio_verify_service_sid: str = ""
    twilio_test_mode: bool = False

    # AI Providers
    openai_api_key: str = ""
    xai_api_key: str = ""

    # App
    debug: bool = False
    api_prefix: str = "/api/v1"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
