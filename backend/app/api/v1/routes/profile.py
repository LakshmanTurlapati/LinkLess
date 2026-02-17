"""Profile API routes for CRUD, photo upload, and social links."""

import logging
import uuid

from botocore.exceptions import BotoCoreError, ClientError
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.schemas.profile import (
    ProfileCreate,
    ProfileResponse,
    ProfileUpdate,
    SocialLinkCreate,
    SocialLinkResponse,
)
from app.services.profile_service import ProfileService
from app.services.storage_service import StorageService

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/profile", tags=["profile"])

# Service instances
_profile_service = ProfileService()


@router.post(
    "",
    response_model=ProfileResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_profile(
    data: ProfileCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ProfileResponse:
    """Create user profile with display name.

    Sets the display_name on the authenticated user's record.
    Photo is uploaded separately via the presign endpoint.
    """
    try:
        updated_user = await _profile_service.create_profile(
            user.id, data, db
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        )

    return ProfileResponse.from_user(updated_user)


@router.get("", response_model=ProfileResponse)
async def get_profile(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ProfileResponse:
    """Get the authenticated user's profile with social links."""
    profile = await _profile_service.get_profile(user.id, db)
    if profile is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found",
        )
    return ProfileResponse.from_user(profile)


@router.patch("", response_model=ProfileResponse)
async def update_profile(
    data: ProfileUpdate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ProfileResponse:
    """Update profile fields (display_name, photo_key, is_anonymous).

    Only non-null fields are updated (partial update semantics).
    When photo_key is provided, it stores only the object key
    in the database. The full URL is constructed at response time.
    """
    try:
        updated_user = await _profile_service.update_profile(
            user.id, data, db
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        )

    return ProfileResponse.from_user(updated_user)


@router.post("/photo/presign")
async def get_photo_upload_url(
    user: User = Depends(get_current_user),
) -> dict:
    """Generate a presigned URL for profile photo upload to Tigris.

    Returns a presigned PUT URL (valid for 5 minutes) and the
    photo_key that should be sent to PATCH /profile after upload.

    Response: { "upload_url": "...", "photo_key": "..." }
    """
    try:
        storage = StorageService()
        result = storage.generate_presigned_upload_url(
            user_id=str(user.id),
            content_type="image/jpeg",
        )
    except (BotoCoreError, ClientError) as exc:
        logger.error("Failed to generate presigned URL: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to generate upload URL. Storage service may be unreachable.",
        ) from exc

    return result


@router.put(
    "/social-links",
    response_model=list[SocialLinkResponse],
)
async def upsert_social_links(
    links: list[SocialLinkCreate],
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[SocialLinkResponse]:
    """Replace all social links for the authenticated user.

    Accepts a list of social links. Deletes all existing links
    and inserts the provided ones (full replace / upsert pattern).

    Only instagram, linkedin, x, and snapchat are accepted as platforms.
    """
    try:
        new_links = await _profile_service.upsert_social_links(
            user.id, links, db
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=str(exc),
        )

    return [
        SocialLinkResponse.model_validate(link) for link in new_links
    ]


@router.get(
    "/social-links",
    response_model=list[SocialLinkResponse],
)
async def get_social_links(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[SocialLinkResponse]:
    """Get all social links for the authenticated user."""
    links = await _profile_service.get_social_links(user.id, db)
    return [
        SocialLinkResponse.model_validate(link) for link in links
    ]


@router.get("/{user_id}", response_model=ProfileResponse)
async def get_peer_profile(
    user_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ProfileResponse:
    """Get another user's public profile by their ID."""
    profile = await _profile_service.get_profile(user_id, db)
    if profile is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Profile not found",
        )
    return ProfileResponse.from_user(profile)
