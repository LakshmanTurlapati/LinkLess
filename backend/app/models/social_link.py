"""SocialLink model for user social media handles."""

import uuid

from sqlalchemy import Boolean, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin


class SocialLink(Base, TimestampMixin):
    """Stores a user's social media platform handle.

    Supported platforms: instagram, linkedin, x, snapchat.
    The is_shared column controls visibility during social exchange (Phase 8).
    """

    __tablename__ = "social_links"
    __table_args__ = (
        UniqueConstraint("user_id", "platform", name="uq_user_platform"),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, default=uuid.uuid4
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    platform: Mapped[str] = mapped_column(String(20))
    handle: Mapped[str] = mapped_column(String(255))
    is_shared: Mapped[bool] = mapped_column(Boolean, default=True)

    user = relationship("User", back_populates="social_links")

    def __repr__(self) -> str:
        return f"<SocialLink id={self.id} platform={self.platform}>"
