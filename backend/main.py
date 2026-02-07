import logging
from contextlib import asynccontextmanager

from arq.connections import RedisSettings, create_pool
from fastapi import FastAPI

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.database import engine

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage application startup and shutdown lifecycle."""
    # Startup: create ARQ connection pool for job enqueuing
    try:
        app.state.arq_pool = await create_pool(
            RedisSettings.from_dsn(settings.redis_url)
        )
        logger.info("ARQ connection pool created")
    except Exception as exc:
        logger.warning("Failed to create ARQ pool: %s. Job enqueuing disabled.", exc)
        app.state.arq_pool = None

    yield

    # Shutdown: close ARQ pool and dispose database engine
    if getattr(app.state, "arq_pool", None) is not None:
        await app.state.arq_pool.close()
        logger.info("ARQ connection pool closed")
    await engine.dispose()


app = FastAPI(
    title="LinkLess API",
    version="0.1.0",
    lifespan=lifespan,
)

app.include_router(api_router, prefix=settings.api_prefix)
