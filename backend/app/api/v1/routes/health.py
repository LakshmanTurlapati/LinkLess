"""Health check endpoint with component-level status and caching.

Reports pass/fail for: database, PostGIS, Redis, Tigris, ARQ worker,
and API key presence. Results are cached for 30 seconds.
"""

import asyncio
import logging
import time
from typing import Optional

from botocore.exceptions import BotoCoreError, ClientError
from fastapi import APIRouter, Depends, Request, Response
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.schemas.health import ApiKeyStatus, ComponentStatus, HealthResponse
from app.services.storage_service import StorageService

logger = logging.getLogger(__name__)

router = APIRouter(tags=["health"])

# Cache state -- module-level for 30-second TTL caching
_HEALTH_CACHE_TTL: float = 30.0
_health_cache: Optional[dict] = None
_health_cache_time: float = 0.0


async def _check_database(db: AsyncSession) -> ComponentStatus:
    """Verify database connectivity with SELECT 1."""
    try:
        await db.execute(text("SELECT 1"))
        return ComponentStatus(status="pass")
    except Exception as exc:
        return ComponentStatus(status="fail", message=str(exc)[:200])


async def _check_postgis(db: AsyncSession) -> ComponentStatus:
    """Verify PostGIS extension availability."""
    try:
        result = await db.execute(text("SELECT PostGIS_Version()"))
        version = result.scalar()
        return ComponentStatus(status="pass", message=f"v{version}")
    except Exception as exc:
        return ComponentStatus(status="fail", message=str(exc)[:200])


async def _check_redis(request: Request) -> ComponentStatus:
    """Verify Redis connectivity via ARQ pool ping with 5s timeout."""
    arq_pool = getattr(request.app.state, "arq_pool", None)
    if arq_pool is None:
        return ComponentStatus(status="fail", message="ARQ pool not initialized")
    try:
        await asyncio.wait_for(arq_pool.ping(), timeout=5.0)
        return ComponentStatus(status="pass")
    except asyncio.TimeoutError:
        return ComponentStatus(status="fail", message="Redis ping timed out (5s)")
    except Exception as exc:
        return ComponentStatus(status="fail", message=str(exc)[:200])


async def _check_tigris() -> ComponentStatus:
    """Verify Tigris bucket access via head_bucket with list_objects_v2 fallback."""
    try:
        storage = StorageService()
        bucket = settings.tigris_bucket

        async def _probe() -> None:
            try:
                await asyncio.to_thread(
                    storage._client.head_bucket, Bucket=bucket
                )
            except (ClientError, BotoCoreError):
                # Fallback: list_objects_v2 with MaxKeys=1
                await asyncio.to_thread(
                    storage._client.list_objects_v2,
                    Bucket=bucket,
                    MaxKeys=1,
                )

        await asyncio.wait_for(_probe(), timeout=5.0)
        return ComponentStatus(status="pass")
    except asyncio.TimeoutError:
        return ComponentStatus(status="fail", message="Tigris check timed out (5s)")
    except Exception as exc:
        return ComponentStatus(status="fail", message=str(exc)[:200])


def _check_api_keys() -> ApiKeyStatus:
    """Check presence of required API keys (env var check only, no API calls)."""
    keys = {
        "openai_api_key": bool(settings.openai_api_key),
        "xai_api_key": bool(settings.xai_api_key),
    }
    all_present = all(keys.values())
    return ApiKeyStatus(
        status="pass" if all_present else "fail",
        keys=keys,
    )


def _compute_aggregate_status(
    database: ComponentStatus,
    postgis: ComponentStatus,
    redis: ComponentStatus,
    tigris: ComponentStatus,
    arq_worker: ComponentStatus,
    api_keys: ApiKeyStatus,
) -> str:
    """Compute aggregate health status.

    Returns:
        "healthy"   -- all components pass
        "unhealthy" -- database or redis fails (critical infrastructure)
        "degraded"  -- only non-critical components fail (tigris, api_keys, postgis)
    """
    all_pass = all(
        c.status == "pass"
        for c in [database, postgis, redis, tigris, arq_worker, api_keys]
    )
    if all_pass:
        return "healthy"

    # Critical: database or redis failure means unhealthy
    if database.status == "fail" or redis.status == "fail":
        return "unhealthy"

    return "degraded"


@router.get("/health", response_model=HealthResponse)
async def health_check(
    request: Request,
    response: Response,
    db: AsyncSession = Depends(get_db),
    _user: User = Depends(get_current_user),
) -> HealthResponse:
    """Check API health with component-level status.

    Requires a valid Bearer token. Results are cached for 30 seconds.
    Returns 503 when aggregate status is not healthy.
    """
    global _health_cache, _health_cache_time

    # Return cached result if fresh
    now = time.monotonic()
    if _health_cache is not None and (now - _health_cache_time) < _HEALTH_CACHE_TTL:
        cached_response = HealthResponse(**_health_cache)
        if cached_response.status != "healthy":
            response.status_code = 503
        return cached_response

    # Run all checks
    database = await _check_database(db)
    postgis = await _check_postgis(db)
    redis_status = await _check_redis(request)
    tigris = await _check_tigris()
    api_keys = _check_api_keys()

    # ARQ worker mirrors Redis status (no heartbeat mechanism)
    if redis_status.status == "pass":
        arq_worker = ComponentStatus(
            status="pass", message="Redis reachable (no heartbeat)"
        )
    else:
        arq_worker = ComponentStatus(
            status="fail", message="Redis unreachable"
        )

    aggregate = _compute_aggregate_status(
        database, postgis, redis_status, tigris, arq_worker, api_keys
    )

    health = HealthResponse(
        status=aggregate,
        database=database,
        postgis=postgis,
        redis=redis_status,
        tigris=tigris,
        arq_worker=arq_worker,
        api_keys=api_keys,
    )

    # Cache the result
    _health_cache = health.model_dump()
    _health_cache_time = now

    if aggregate != "healthy":
        response.status_code = 503

    return health
