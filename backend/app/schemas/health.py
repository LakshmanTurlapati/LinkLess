from typing import Optional

from pydantic import BaseModel


class ComponentStatus(BaseModel):
    """Status of a single infrastructure component."""

    status: str  # "pass" or "fail"
    message: Optional[str] = None


class ApiKeyStatus(BaseModel):
    """Status of API key presence checks."""

    status: str  # "pass" or "fail"
    keys: dict[str, bool]


class HealthResponse(BaseModel):
    """Response schema for the health check endpoint.

    Provides component-level pass/fail status for all infrastructure
    dependencies and an aggregate status field.
    """

    status: str  # "healthy", "degraded", or "unhealthy"
    database: ComponentStatus
    postgis: ComponentStatus
    redis: ComponentStatus
    tigris: ComponentStatus
    arq_worker: ComponentStatus
    api_keys: ApiKeyStatus
