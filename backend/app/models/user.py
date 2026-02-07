"""User model for the users table."""

import uuid
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.models.base import Base, TimestampMixin

if TYPE_CHECKING:
    from app.models.refresh_token import RefreshToken
    from app.models.social_link import SocialLink


class User(Base, TimestampMixin):
    """Represents an application user."""

    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, default=uuid.uuid4
    )
    phone_number: Mapped[str] = mapped_column(
        String(20), unique=True, index=True
    )
    display_name: Mapped[str | None] = mapped_column(
        String(100), nullable=True
    )
    photo_url: Mapped[str | None] = mapped_column(
        String(512), nullable=True
    )
    is_anonymous: Mapped[bool] = mapped_column(Boolean, default=False)
    is_active: Mapped[bool] = mapped_column(Boolean, default=True)

    refresh_tokens: Mapped[list["RefreshToken"]] = relationship(
        "RefreshToken", back_populates="user", lazy="selectin"
    )
    social_links: Mapped[list["SocialLink"]] = relationship(
        "SocialLink",
        back_populates="user",
        cascade="all, delete-orphan",
        lazy="selectin",
    )

    def __repr__(self) -> str:
        return f"<User id={self.id} phone={self.phone_number}>"
