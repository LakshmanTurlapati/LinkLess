"""Update social_links table for profile feature.

Revision ID: 003_update_social_links
Revises: 002_create_core_tables
Create Date: 2026-02-07

Changes:
- Rename is_visible to is_shared in social_links (for Phase 8 social exchange)
- Narrow platform column from VARCHAR(50) to VARCHAR(20) to enforce limits
- Add unique constraint on (user_id, platform) -- one link per platform per user
- Replace FK on user_id to include ON DELETE CASCADE

"""

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "003_update_social_links"
down_revision: Union[str, Sequence[str], None] = "002_create_core_tables"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Apply profile-related schema updates to social_links."""
    # Rename is_visible -> is_shared
    op.alter_column(
        "social_links",
        "is_visible",
        new_column_name="is_shared",
    )

    # Narrow platform column from VARCHAR(50) to VARCHAR(20)
    op.alter_column(
        "social_links",
        "platform",
        existing_type=sa.String(length=50),
        type_=sa.String(length=20),
        existing_nullable=False,
    )

    # Add unique constraint: one link per platform per user
    op.create_unique_constraint(
        "uq_user_platform",
        "social_links",
        ["user_id", "platform"],
    )

    # Drop old FK and re-add with ON DELETE CASCADE
    op.drop_constraint(
        "social_links_user_id_fkey",
        "social_links",
        type_="foreignkey",
    )
    op.create_foreign_key(
        "social_links_user_id_fkey",
        "social_links",
        "users",
        ["user_id"],
        ["id"],
        ondelete="CASCADE",
    )


def downgrade() -> None:
    """Revert profile-related schema updates from social_links."""
    # Revert FK back to no ON DELETE CASCADE
    op.drop_constraint(
        "social_links_user_id_fkey",
        "social_links",
        type_="foreignkey",
    )
    op.create_foreign_key(
        "social_links_user_id_fkey",
        "social_links",
        "users",
        ["user_id"],
        ["id"],
    )

    # Drop unique constraint
    op.drop_constraint(
        "uq_user_platform",
        "social_links",
        type_="unique",
    )

    # Widen platform column back to VARCHAR(50)
    op.alter_column(
        "social_links",
        "platform",
        existing_type=sa.String(length=20),
        type_=sa.String(length=50),
        existing_nullable=False,
    )

    # Rename is_shared -> is_visible
    op.alter_column(
        "social_links",
        "is_shared",
        new_column_name="is_visible",
    )
