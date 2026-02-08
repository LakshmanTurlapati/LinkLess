"""BlockedUser model for tracking blocked users."""

import uuid

from sqlalchemy import ForeignKey, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin


class BlockedUser(Base, TimestampMixin):
    """Records that a user has blocked another user from proximity detection.

    When a user blocks another, BLE proximity detection is skipped for the
    blocked user, and connection requests between them are declined.
    """

    __tablename__ = "blocked_users"
    __table_args__ = (
        UniqueConstraint(
            "blocker_id", "blocked_id", name="uq_blocker_blocked"
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, default=uuid.uuid4
    )
    blocker_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    blocked_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )

    def __repr__(self) -> str:
        return f"<BlockedUser id={self.id} blocker={self.blocker_id}>"
