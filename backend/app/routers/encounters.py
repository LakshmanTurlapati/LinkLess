"""Encounter management endpoints."""

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select, or_, func
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.database import get_db
from app.models import User, Encounter, EncounterStatus
from app.schemas import CreateEncounterRequest
from app.auth_utils import get_current_user

router = APIRouter()


@router.post("")
async def create_encounter(
    request: CreateEncounterRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Create a new encounter when two LinkLess users are detected in proximity."""
    # Verify the peer exists
    result = await db.execute(select(User).where(User.id == request.peer_id))
    peer = result.scalar_one_or_none()

    if not peer:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Peer user not found",
        )

    if request.peer_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot create encounter with yourself",
        )

    # Check for existing active encounter between these users
    result = await db.execute(
        select(Encounter).where(
            Encounter.status == EncounterStatus.ACTIVE,
            or_(
                (Encounter.user_id == current_user.id)
                & (Encounter.peer_id == request.peer_id),
                (Encounter.user_id == request.peer_id)
                & (Encounter.peer_id == current_user.id),
            ),
        )
    )
    existing = result.scalar_one_or_none()

    if existing:
        # Return the existing active encounter
        return existing.to_dict(include_peer=True)

    encounter = Encounter(
        user_id=current_user.id,
        peer_id=request.peer_id,
        proximity_distance=request.proximity_distance,
    )
    db.add(encounter)
    await db.flush()

    # Reload with relationships
    result = await db.execute(
        select(Encounter)
        .where(Encounter.id == encounter.id)
        .options(selectinload(Encounter.peer), selectinload(Encounter.transcript_segments))
    )
    encounter = result.scalar_one()

    return encounter.to_dict(include_peer=True)


@router.get("")
async def list_encounters(
    page: int = Query(1, ge=1),
    per_page: int = Query(20, ge=1, le=100),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """List all encounters for the current user."""
    # Count total
    count_result = await db.execute(
        select(func.count(Encounter.id)).where(
            or_(
                Encounter.user_id == current_user.id,
                Encounter.peer_id == current_user.id,
            )
        )
    )
    total = count_result.scalar()

    # Fetch paginated results
    offset = (page - 1) * per_page
    result = await db.execute(
        select(Encounter)
        .where(
            or_(
                Encounter.user_id == current_user.id,
                Encounter.peer_id == current_user.id,
            )
        )
        .options(
            selectinload(Encounter.peer),
            selectinload(Encounter.user),
            selectinload(Encounter.transcript_segments),
        )
        .order_by(Encounter.started_at.desc())
        .offset(offset)
        .limit(per_page)
    )
    encounters = result.scalars().all()

    return {
        "encounters": [e.to_dict(include_peer=True) for e in encounters],
        "total": total,
        "page": page,
        "per_page": per_page,
    }


@router.get("/{encounter_id}")
async def get_encounter(
    encounter_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Get a specific encounter with full transcript."""
    result = await db.execute(
        select(Encounter)
        .where(Encounter.id == encounter_id)
        .options(
            selectinload(Encounter.peer),
            selectinload(Encounter.user),
            selectinload(Encounter.transcript_segments),
        )
    )
    encounter = result.scalar_one_or_none()

    if not encounter:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Encounter not found",
        )

    # Only participants can view
    if encounter.user_id != current_user.id and encounter.peer_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to view this encounter",
        )

    return encounter.to_dict(include_peer=True)


@router.post("/{encounter_id}/end")
async def end_encounter(
    encounter_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """End an active encounter (triggered when users move apart)."""
    result = await db.execute(
        select(Encounter)
        .where(Encounter.id == encounter_id)
        .options(selectinload(Encounter.transcript_segments))
    )
    encounter = result.scalar_one_or_none()

    if not encounter:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Encounter not found",
        )

    if encounter.user_id != current_user.id and encounter.peer_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to end this encounter",
        )

    if encounter.status != EncounterStatus.ACTIVE:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Encounter is not active",
        )

    encounter.status = EncounterStatus.COMPLETED
    encounter.ended_at = datetime.utcnow()
    await db.flush()

    return encounter.to_dict(include_peer=True)
