from fastapi import APIRouter, Depends
from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.schemas.health import HealthResponse

router = APIRouter(tags=["health"])


@router.get("/health", response_model=HealthResponse)
async def health_check(db: AsyncSession = Depends(get_db)) -> HealthResponse:
    """Check API health, database connectivity, and PostGIS availability."""

    # Verify database connectivity
    try:
        await db.execute(text("SELECT 1"))
        db_status = "connected"
    except Exception:
        db_status = "disconnected"

    # Verify PostGIS extension
    try:
        result = await db.execute(text("SELECT PostGIS_Version()"))
        row = result.scalar()
        postgis_status = f"enabled (v{row})"
    except Exception:
        postgis_status = "not available"

    status = "healthy" if db_status == "connected" else "degraded"

    return HealthResponse(
        status=status,
        database=db_status,
        postgis=postgis_status,
    )
