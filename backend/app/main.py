"""LinkLess Backend API — FastAPI application entry point."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import settings
from app.database import engine, Base
from app.routers import auth, users, encounters, transcription


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Create database tables on startup."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    await engine.dispose()


app = FastAPI(
    title="LinkLess API",
    description="Backend API for LinkLess — proximity-based conversation capture",
    version="1.0.0",
    lifespan=lifespan,
)

# CORS — allow mobile app to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mount routers
app.include_router(auth.router, prefix="/v1/auth", tags=["Authentication"])
app.include_router(users.router, prefix="/v1/users", tags=["Users"])
app.include_router(encounters.router, prefix="/v1/encounters", tags=["Encounters"])
app.include_router(
    transcription.router, prefix="/v1/encounters", tags=["Transcription"]
)


@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": "linkless-api"}
