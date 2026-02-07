"""Create core tables.

Revision ID: 002_create_core_tables
Revises: 001_enable_postgis
Create Date: 2026-02-07

"""

from typing import Sequence, Union

import geoalchemy2
import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision: str = "002_create_core_tables"
down_revision: Union[str, Sequence[str], None] = "001_enable_postgis"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create users, conversations, transcripts, summaries, and social_links tables."""
    # -- users --
    op.create_table(
        "users",
        sa.Column("id", sa.Uuid(), nullable=False, default=sa.text("gen_random_uuid()")),
        sa.Column("phone_number", sa.String(length=20), nullable=False),
        sa.Column("display_name", sa.String(length=100), nullable=True),
        sa.Column("photo_url", sa.String(length=512), nullable=True),
        sa.Column("is_anonymous", sa.Boolean(), nullable=False, server_default=sa.text("false")),
        sa.Column("is_active", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("phone_number"),
    )
    op.create_index(op.f("ix_users_phone_number"), "users", ["phone_number"], unique=True)

    # -- conversations --
    op.create_table(
        "conversations",
        sa.Column("id", sa.Uuid(), nullable=False, default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("peer_user_id", sa.Uuid(), nullable=True),
        sa.Column(
            "location",
            geoalchemy2.types.Geometry(
                geometry_type="POINT",
                srid=4326,
                from_text="ST_GeomFromEWKT",
                name="geometry",
            ),
            nullable=True,
        ),
        sa.Column("started_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ended_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("duration_seconds", sa.Integer(), nullable=True),
        sa.Column("audio_storage_key", sa.String(length=512), nullable=True),
        sa.Column("status", sa.String(length=50), nullable=False, server_default=sa.text("'pending'")),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
        sa.ForeignKeyConstraint(["peer_user_id"], ["users.id"]),
    )
    op.create_index(op.f("ix_conversations_user_id"), "conversations", ["user_id"])

    # -- transcripts --
    op.create_table(
        "transcripts",
        sa.Column("id", sa.Uuid(), nullable=False, default=sa.text("gen_random_uuid()")),
        sa.Column("conversation_id", sa.Uuid(), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("provider", sa.String(length=50), nullable=False),
        sa.Column("language", sa.String(length=10), nullable=False, server_default=sa.text("'en'")),
        sa.Column("word_count", sa.Integer(), nullable=True),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(
            ["conversation_id"],
            ["conversations.id"],
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint("conversation_id"),
    )
    op.create_index(
        op.f("ix_transcripts_conversation_id"),
        "transcripts",
        ["conversation_id"],
        unique=True,
    )

    # -- summaries --
    op.create_table(
        "summaries",
        sa.Column("id", sa.Uuid(), nullable=False, default=sa.text("gen_random_uuid()")),
        sa.Column("conversation_id", sa.Uuid(), nullable=False),
        sa.Column("content", sa.Text(), nullable=False),
        sa.Column("key_topics", sa.Text(), nullable=True),
        sa.Column("provider", sa.String(length=50), nullable=False),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(
            ["conversation_id"],
            ["conversations.id"],
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint("conversation_id"),
    )
    op.create_index(
        op.f("ix_summaries_conversation_id"),
        "summaries",
        ["conversation_id"],
        unique=True,
    )

    # -- social_links --
    op.create_table(
        "social_links",
        sa.Column("id", sa.Uuid(), nullable=False, default=sa.text("gen_random_uuid()")),
        sa.Column("user_id", sa.Uuid(), nullable=False),
        sa.Column("platform", sa.String(length=50), nullable=False),
        sa.Column("handle", sa.String(length=255), nullable=False),
        sa.Column("is_visible", sa.Boolean(), nullable=False, server_default=sa.text("true")),
        sa.Column("created_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at", sa.DateTime(), nullable=False, server_default=sa.func.now()),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(["user_id"], ["users.id"]),
    )
    op.create_index(op.f("ix_social_links_user_id"), "social_links", ["user_id"])


def downgrade() -> None:
    """Drop all core tables in reverse dependency order."""
    op.drop_index(op.f("ix_social_links_user_id"), table_name="social_links")
    op.drop_table("social_links")

    op.drop_index(op.f("ix_summaries_conversation_id"), table_name="summaries")
    op.drop_table("summaries")

    op.drop_index(op.f("ix_transcripts_conversation_id"), table_name="transcripts")
    op.drop_table("transcripts")

    op.drop_index(op.f("ix_conversations_user_id"), table_name="conversations")
    op.drop_table("conversations")

    op.drop_index(op.f("ix_users_phone_number"), table_name="users")
    op.drop_table("users")
