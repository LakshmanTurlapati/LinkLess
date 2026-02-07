"""User model for the users table."""

import uuid

from sqlalchemy import Boolean, String
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin


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

    def __repr__(self) -> str:
        return f"<User id={self.id} phone={self.phone_number}>"
