"""ARQ async task queue worker configuration.

Start the worker with:
    arq app.tasks.worker.WorkerSettings

Requires Redis to be running and accessible at the URL configured
in settings.redis_url.
"""

import logging

from arq.connections import RedisSettings, create_pool
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.core.config import settings
from app.tasks.summarization import summarize_conversation
from app.tasks.transcription import transcribe_conversation

logger = logging.getLogger(__name__)


async def startup(ctx: dict) -> None:
    """Worker startup hook. Creates DB session factory and Redis pool.

    Called once when the worker process starts. Stores shared resources
    in the context dict for use by all task functions.
    """
    engine = create_async_engine(
        settings.database_url,
        echo=settings.debug,
        pool_pre_ping=True,
    )
    ctx["engine"] = engine
    ctx["db_session_factory"] = async_sessionmaker(
        engine, expire_on_commit=False
    )

    ctx["redis"] = await create_pool(
        RedisSettings.from_dsn(settings.redis_url)
    )

    logger.info("Worker started with DB and Redis connections")


async def shutdown(ctx: dict) -> None:
    """Worker shutdown hook. Disposes of the database engine.

    Called once when the worker process stops. Cleans up shared resources.
    """
    engine = ctx.get("engine")
    if engine is not None:
        await engine.dispose()
    logger.info("Worker stopped, DB engine disposed")


class WorkerSettings:
    """ARQ worker settings.

    Configures the task queue worker with Redis connection,
    registered task functions, and lifecycle hooks.
    """

    functions = [transcribe_conversation, summarize_conversation]
    on_startup = startup
    on_shutdown = shutdown
    redis_settings = RedisSettings.from_dsn(settings.redis_url)
    max_jobs = 5
    job_timeout = 600  # 10 minutes
