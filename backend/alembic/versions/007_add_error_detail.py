"""Add error_detail column to conversations table.

Revision ID: 007_add_error_detail
Revises: 006_create_refresh_tokens
Create Date: 2026-02-21

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "007_add_error_detail"
down_revision: Union[str, Sequence[str], None] = "006_create_refresh_tokens"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add error_detail column for failure tracking."""
    op.add_column(
        "conversations",
        sa.Column("error_detail", sa.Text(), nullable=True),
    )


def downgrade() -> None:
    """Remove error_detail column."""
    op.drop_column("conversations", "error_detail")
