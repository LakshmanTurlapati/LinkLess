"""Add search_vector tsvector columns to transcripts and summaries.

Revision ID: 005_add_search_vector
Revises: 004_create_connection_tables
Create Date: 2026-02-08

Changes:
- Add search_vector GENERATED ALWAYS AS tsvector column to transcripts
- Add search_vector GENERATED ALWAYS AS tsvector column to summaries
- Create GIN indexes on both search_vector columns for full-text search

Uses raw SQL via op.execute() because Alembic has known issues with
tsvector expression columns and Computed().
"""

from typing import Sequence, Union

from alembic import op

# revision identifiers, used by Alembic.
revision: str = "005_add_search_vector"
down_revision: Union[str, Sequence[str], None] = "004_create_connection_tables"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Add tsvector search columns and GIN indexes."""
    # Transcript search vector: indexes transcript content
    op.execute(
        """
        ALTER TABLE transcripts ADD COLUMN search_vector tsvector
          GENERATED ALWAYS AS (to_tsvector('english', coalesce(content, ''))) STORED
        """
    )
    op.execute(
        """
        CREATE INDEX ix_transcripts_search_vector
          ON transcripts USING gin(search_vector)
        """
    )

    # Summary search vector: indexes summary content and key_topics
    op.execute(
        """
        ALTER TABLE summaries ADD COLUMN search_vector tsvector
          GENERATED ALWAYS AS (
            to_tsvector('english', coalesce(content, '') || ' ' || coalesce(key_topics, ''))
          ) STORED
        """
    )
    op.execute(
        """
        CREATE INDEX ix_summaries_search_vector
          ON summaries USING gin(search_vector)
        """
    )


def downgrade() -> None:
    """Remove search_vector columns and GIN indexes."""
    op.execute("DROP INDEX IF EXISTS ix_summaries_search_vector")
    op.execute("ALTER TABLE summaries DROP COLUMN IF EXISTS search_vector")
    op.execute("DROP INDEX IF EXISTS ix_transcripts_search_vector")
    op.execute("ALTER TABLE transcripts DROP COLUMN IF EXISTS search_vector")
