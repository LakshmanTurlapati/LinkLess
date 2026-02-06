"""User profile endpoints."""

import os
import uuid
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.config import settings
from app.database import get_db
from app.models import User, PrivacyMode
from app.schemas import UpdateProfileRequest
from app.auth_utils import get_current_user

router = APIRouter()


@router.get("/me")
async def get_current_profile(current_user: User = Depends(get_current_user)):
    """Get the current user's full profile."""
    return current_user.to_dict(include_email=True)


@router.put("/me")
async def update_profile(
    request: UpdateProfileRequest,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Update the current user's profile."""
    if request.display_name is not None:
        current_user.display_name = request.display_name
    if request.bio is not None:
        current_user.bio = request.bio
    if request.privacy_mode is not None:
        try:
            current_user.privacy_mode = PrivacyMode(request.privacy_mode)
        except ValueError:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="Invalid privacy mode. Use 'public' or 'anonymous'.",
            )
    if request.social_links is not None:
        # Validate social links structure
        allowed_keys = {"instagram", "twitter", "linkedin", "github", "website"}
        if not all(k in allowed_keys for k in request.social_links.keys()):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Invalid social link keys. Allowed: {allowed_keys}",
            )
        current_user.social_links = request.social_links

    current_user.updated_at = datetime.utcnow()
    await db.flush()

    return current_user.to_dict(include_email=True)


@router.post("/me/photo")
async def upload_profile_photo(
    photo: UploadFile = File(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """Upload a profile photo."""
    # Validate file type
    if photo.content_type not in ("image/jpeg", "image/png", "image/webp"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Only JPEG, PNG, and WebP images are accepted",
        )

    # Read and save file
    os.makedirs(settings.upload_dir, exist_ok=True)
    ext = photo.filename.rsplit(".", 1)[-1] if photo.filename else "jpg"
    filename = f"{current_user.id}_{uuid.uuid4().hex[:8]}.{ext}"
    file_path = os.path.join(settings.upload_dir, filename)

    content = await photo.read()
    with open(file_path, "wb") as f:
        f.write(content)

    # In production, upload to cloud storage and get URL
    photo_url = f"/uploads/{filename}"
    current_user.photo_url = photo_url
    current_user.updated_at = datetime.utcnow()
    await db.flush()

    return {"photo_url": photo_url}


@router.get("/{user_id}")
async def get_user_profile(
    user_id: str,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Get another user's public profile."""
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    # Return profile respecting privacy settings
    return user.to_dict()
