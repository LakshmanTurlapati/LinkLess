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

    # App
    debug: bool = False
    api_prefix: str = "/api/v1"

    model_config = {"env_file": ".env", "env_file_encoding": "utf-8"}


@lru_cache
def get_settings() -> Settings:
    return Settings()


settings = get_settings()
