"""ARQ async task queue worker configuration.

Start the worker with:
    arq app.tasks.worker.WorkerSettings

Requires Redis to be running and accessible at the URL configured
in settings.redis_url.
"""

import logging

from arq import Retry
from arq.connections import RedisSettings

from app.core.config import settings

logger = logging.getLogger(__name__)


async def example_task(ctx: dict, message: str) -> str:
    """Placeholder task for verifying worker connectivity.

    This will be replaced by real tasks (e.g., transcription) in Phase 6.

    Args:
        ctx: ARQ worker context dictionary.
        message: A test message to echo back.

    Returns:
        The echoed message string.
    """
    logger.info("example_task received: %s", message)
    return f"Processed: {message}"


async def startup(ctx: dict) -> None:
    """Worker startup hook. Called once when the worker process starts."""
    logger.info("Worker started")


async def shutdown(ctx: dict) -> None:
    """Worker shutdown hook. Called once when the worker process stops."""
    logger.info("Worker stopped")


class WorkerSettings:
    """ARQ worker settings.

    Configures the task queue worker with Redis connection,
    registered task functions, and lifecycle hooks.
    """

    functions = [example_task]
    on_startup = startup
    on_shutdown = shutdown
    redis_settings = RedisSettings.from_dsn(settings.redis_url)
    max_jobs = 10
    job_timeout = 300  # 5 minutes
