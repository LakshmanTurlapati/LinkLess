"""Profile business logic for CRUD operations and social links."""

import logging
import uuid as uuid_mod
from typing import Optional

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models.social_link import SocialLink
from app.models.user import User
from app.schemas.profile import ProfileCreate, ProfileUpdate, SocialLinkCreate

logger = logging.getLogger(__name__)

ALLOWED_PLATFORMS = frozenset({"instagram", "linkedin", "x", "snapchat"})


class ProfileService:
    """Handles profile and social link CRUD operations.

    All methods operate on the User and SocialLink models,
    applying business rules like platform whitelisting and
    partial update semantics.
    """

    async def get_profile(
        self, user_id: uuid_mod.UUID, db: AsyncSession
    ) -> Optional[User]:
        """Fetch a user profile with eagerly-loaded social links.

        Args:
            user_id: The user's UUID.
            db: Async database session.

        Returns:
            The User object with social_links loaded, or None.
        """
        stmt = (
            select(User)
            .where(User.id == user_id)
            .options(selectinload(User.social_links))
        )
        result = await db.execute(stmt)
        return result.scalar_one_or_none()

    async def create_profile(
        self, user_id: uuid_mod.UUID, data: ProfileCreate, db: AsyncSession
    ) -> User:
        """Set display_name on an existing user record.

        Args:
            user_id: The user's UUID.
            data: ProfileCreate schema with display_name.
            db: Async database session.

        Returns:
            Updated User object with social_links loaded.

        Raises:
            ValueError: If user not found.
        """
        user = await self.get_profile(user_id, db)
        if user is None:
            raise ValueError(f"User {user_id} not found")

        user.display_name = data.display_name
        await db.commit()
        await db.refresh(user)
        # Re-fetch with eager loading after refresh
        return await self.get_profile(user_id, db)  # type: ignore[return-value]

    async def update_profile(
        self, user_id: uuid_mod.UUID, data: ProfileUpdate, db: AsyncSession
    ) -> User:
        """Update only non-None profile fields.

        When photo_key is provided, stores ONLY the object key in
        photo_url (not the full URL). Full URL is constructed at
        response time in the schema.

        Args:
            user_id: The user's UUID.
            data: ProfileUpdate schema with optional fields.
            db: Async database session.

        Returns:
            Updated User object with social_links loaded.

        Raises:
            ValueError: If user not found.
        """
        user = await self.get_profile(user_id, db)
        if user is None:
            raise ValueError(f"User {user_id} not found")

        if data.display_name is not None:
            user.display_name = data.display_name
        if data.photo_key is not None:
            # Store only the object key, NOT the full URL
            user.photo_url = data.photo_key
        if data.is_anonymous is not None:
            user.is_anonymous = data.is_anonymous

        await db.commit()
        await db.refresh(user)
        return await self.get_profile(user_id, db)  # type: ignore[return-value]

    async def upsert_social_links(
        self,
        user_id: uuid_mod.UUID,
        links: list[SocialLinkCreate],
        db: AsyncSession,
    ) -> list[SocialLink]:
        """Replace all social links for a user (upsert pattern).

        Validates all platforms against the allowlist, deletes existing
        links, and inserts the new set.

        Args:
            user_id: The user's UUID.
            links: List of SocialLinkCreate schemas.
            db: Async database session.

        Returns:
            List of newly created SocialLink objects.

        Raises:
            ValueError: If any platform is not in the allowlist.
        """
        # Validate all platforms before making any changes
        for link in links:
            if link.platform not in ALLOWED_PLATFORMS:
                raise ValueError(
                    f"Invalid platform: {link.platform}. "
                    f"Allowed: {', '.join(sorted(ALLOWED_PLATFORMS))}"
                )

        # Delete existing links for this user
        await db.execute(
            delete(SocialLink).where(SocialLink.user_id == user_id)
        )

        # Insert new links
        new_links: list[SocialLink] = []
        for link in links:
            social_link = SocialLink(
                user_id=user_id,
                platform=link.platform,
                handle=link.handle,
            )
            db.add(social_link)
            new_links.append(social_link)

        await db.commit()

        # Refresh to get generated IDs
        for sl in new_links:
            await db.refresh(sl)

        return new_links

    async def get_social_links(
        self, user_id: uuid_mod.UUID, db: AsyncSession
    ) -> list[SocialLink]:
        """Fetch all social links for a user.

        Args:
            user_id: The user's UUID.
            db: Async database session.

        Returns:
            List of SocialLink objects.
        """
        result = await db.execute(
            select(SocialLink).where(SocialLink.user_id == user_id)
        )
        return list(result.scalars().all())
