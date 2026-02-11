from functools import lru_cache
from urllib.parse import parse_qs, urlencode, urlparse, urlunparse

from pydantic import model_validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    # Database
    database_url: str = (
        "postgresql+asyncpg://linkless:linkless@localhost:5432/linkless"
    )

    @model_validator(mode="after")
    def fix_database_url(self) -> "Settings":
        """Rewrite DATABASE_URL for asyncpg compatibility.

        Fly.io sets postgres:// scheme and ?sslmode=disable; asyncpg needs
        postgresql+asyncpg:// and does not accept the sslmode query param.
        """
        url = self.database_url
        if url.startswith("postgres://"):
            url = "postgresql+asyncpg://" + url[len("postgres://"):]
        elif url.startswith("postgresql://"):
            url = "postgresql+asyncpg://" + url[len("postgresql://"):]
        # Translate sslmode (libpq) to ssl (asyncpg) in query params
        parsed = urlparse(url)
        params = parse_qs(parsed.query)
        sslmode = params.pop("sslmode", [None])[0]
        if sslmode and "ssl" not in params:
            params["ssl"] = [sslmode]
        cleaned_query = urlencode(params, doseq=True)
        self.database_url = urlunparse(parsed._replace(query=cleaned_query))
        return self

    # Redis
    redis_url: str = "redis://localhost:6379"

    # Tigris Object Storage
    tigris_endpoint: str = "https://fly.storage.tigris.dev"
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
