"""SocialLink model for user social media handles."""

import uuid

from sqlalchemy import Boolean, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin


class SocialLink(Base, TimestampMixin):
    """Stores a user's social media platform handle."""

    __tablename__ = "social_links"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id"), index=True
    )
    platform: Mapped[str] = mapped_column(String(50))
    handle: Mapped[str] = mapped_column(String(255))
    is_visible: Mapped[bool] = mapped_column(Boolean, default=True)

    def __repr__(self) -> str:
        return f"<SocialLink id={self.id} platform={self.platform}>"
