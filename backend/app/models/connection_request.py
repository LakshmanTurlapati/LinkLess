"""ConnectionRequest model for tracking connection requests between users."""

import uuid

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.models.base import Base, TimestampMixin


class ConnectionRequest(Base, TimestampMixin):
    """Represents one user's intent to connect with another after a conversation.

    Each conversation can produce two ConnectionRequest rows (one per participant).
    When both have status='accepted', social links are exchanged.
    Status values: pending, accepted, declined.
    """

    __tablename__ = "connection_requests"
    __table_args__ = (
        UniqueConstraint(
            "requester_id",
            "conversation_id",
            name="uq_requester_conversation",
        ),
    )

    id: Mapped[uuid.UUID] = mapped_column(
        primary_key=True, default=uuid.uuid4
    )
    requester_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    recipient_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True
    )
    conversation_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("conversations.id", ondelete="CASCADE"), index=True
    )
    status: Mapped[str] = mapped_column(String(20), default="pending")

    def __repr__(self) -> str:
        return f"<ConnectionRequest id={self.id} status={self.status}>"
