"""Create connection_requests and blocked_users tables.

Revision ID: 004_create_connection_tables
Revises: 003_update_social_links
Create Date: 2026-02-08

Changes:
- Create connection_requests table with unique constraint on (requester_id, conversation_id)
- Create blocked_users table with unique constraint on (blocker_id, blocked_id)
- Add indexes on foreign key columns for query performance

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "004_create_connection_tables"
down_revision: Union[str, Sequence[str], None] = "003_update_social_links"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create connection_requests and blocked_users tables."""
    # Create connection_requests table
    op.create_table(
        "connection_requests",
        sa.Column(
            "id",
            sa.Uuid(),
            primary_key=True,
            nullable=False,
        ),
        sa.Column(
            "requester_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column(
            "recipient_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column(
            "conversation_id",
            sa.Uuid(),
            sa.ForeignKey("conversations.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column(
            "status",
            sa.String(20),
            nullable=False,
            server_default="pending",
        ),
        sa.Column(
            "created_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint(
            "requester_id",
            "conversation_id",
            name="uq_requester_conversation",
        ),
    )

    # Create blocked_users table
    op.create_table(
        "blocked_users",
        sa.Column(
            "id",
            sa.Uuid(),
            primary_key=True,
            nullable=False,
        ),
        sa.Column(
            "blocker_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column(
            "blocked_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.UniqueConstraint(
            "blocker_id",
            "blocked_id",
            name="uq_blocker_blocked",
        ),
    )


def downgrade() -> None:
    """Drop connection_requests and blocked_users tables."""
    op.drop_table("blocked_users")
    op.drop_table("connection_requests")
