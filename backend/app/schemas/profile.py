"""Pydantic schemas for profile and social link endpoints."""

from __future__ import annotations

import uuid
from typing import Optional

from pydantic import BaseModel, field_validator

from app.services.storage_service import StorageService

ALLOWED_PLATFORMS = {"instagram", "linkedin", "x", "snapchat"}


class ProfileCreate(BaseModel):
    """Request body for POST /profile (create profile with display name)."""

    display_name: str

    @field_validator("display_name")
    @classmethod
    def validate_display_name(cls, v: str) -> str:
        v = v.strip()
        if len(v) < 1 or len(v) > 100:
            raise ValueError("Display name must be 1-100 characters")
        return v


class ProfileUpdate(BaseModel):
    """Request body for PATCH /profile (partial update).

    All fields are optional; only non-None fields are applied.
    """

    display_name: Optional[str] = None
    photo_key: Optional[str] = None
    is_anonymous: Optional[bool] = None

    @field_validator("display_name")
    @classmethod
    def validate_display_name(cls, v: Optional[str]) -> Optional[str]:
        if v is not None:
            v = v.strip()
            if len(v) < 1 or len(v) > 100:
                raise ValueError("Display name must be 1-100 characters")
        return v


class SocialLinkCreate(BaseModel):
    """Request body for a single social link in PUT /profile/social-links."""

    platform: str
    handle: str

    @field_validator("platform")
    @classmethod
    def validate_platform(cls, v: str) -> str:
        v = v.strip().lower()
        if v not in ALLOWED_PLATFORMS:
            raise ValueError(
                f"Platform must be one of: {', '.join(sorted(ALLOWED_PLATFORMS))}"
            )
        return v

    @field_validator("handle")
    @classmethod
    def validate_handle(cls, v: str) -> str:
        v = v.strip().lstrip("@")
        if len(v) < 1 or len(v) > 255:
            raise ValueError("Handle must be 1-255 characters")
        return v


class SocialLinkResponse(BaseModel):
    """Response schema for a single social link."""

    id: uuid.UUID
    platform: str
    handle: str

    model_config = {"from_attributes": True}


class ProfileResponse(BaseModel):
    """Response schema for profile endpoints.

    When is_anonymous is True, display_name is masked (set to None)
    but initials are always derived from the stored name.
    Photo URL is constructed from the stored object key at response time.
    """

    id: uuid.UUID
    display_name: Optional[str]
    initials: Optional[str]
    photo_url: Optional[str]
    is_anonymous: bool
    social_links: list[SocialLinkResponse] = []

    model_config = {"from_attributes": True}

    @classmethod
    def from_user(cls, user: object) -> ProfileResponse:
        """Build a ProfileResponse from a User ORM model.

        Handles anonymous mode masking and photo URL construction.
        """
        # Derive initials from the stored display_name
        initials: Optional[str] = None
        stored_name: Optional[str] = getattr(user, "display_name", None)
        if stored_name:
            parts = stored_name.strip().split()
            initials = "".join(p[0].upper() for p in parts[:2])

        # Determine visible display_name based on anonymous mode
        visible_name = stored_name
        is_anonymous: bool = getattr(user, "is_anonymous", False)
        if is_anonymous:
            visible_name = None

        # Construct full photo URL from stored key
        photo_key: Optional[str] = getattr(user, "photo_url", None)
        photo_url: Optional[str] = None
        if photo_key:
            storage = StorageService()
            photo_url = storage.get_public_url(photo_key)

        # Build social link responses
        raw_links = getattr(user, "social_links", [])
        social_links = [
            SocialLinkResponse.model_validate(link) for link in raw_links
        ]

        return cls(
            id=user.id,  # type: ignore[attr-defined]
            display_name=visible_name,
            initials=initials,
            photo_url=photo_url,
            is_anonymous=is_anonymous,
            social_links=social_links,
        )
