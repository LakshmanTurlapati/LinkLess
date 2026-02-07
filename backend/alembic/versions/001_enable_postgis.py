"""Enable PostGIS extension.

Revision ID: 001_enable_postgis
Revises:
Create Date: 2026-02-07

"""

from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "001_enable_postgis"
down_revision: Union[str, Sequence[str], None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Enable the PostGIS extension for spatial operations."""
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")


def downgrade() -> None:
    """Remove the PostGIS extension."""
    op.execute("DROP EXTENSION IF EXISTS postgis")
