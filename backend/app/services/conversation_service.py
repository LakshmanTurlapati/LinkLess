"""Conversation business logic for CRUD operations and status management."""

import datetime as dt_mod
import logging
import uuid as uuid_mod
from typing import Optional

from geoalchemy2 import WKTElement
from sqlalchemy import Date, cast, delete, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.models.conversation import Conversation, Summary, Transcript
from app.models.user import User
from app.schemas.conversation import ConversationCreate

logger = logging.getLogger(__name__)


class ConversationService:
    """Handles conversation lifecycle operations.

    All methods operate on the Conversation, Transcript, and Summary
    models, managing status transitions and data retrieval.
    """

    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def create_conversation(
        self, data: ConversationCreate
    ) -> Conversation:
        """Create a new conversation record with pending status.

        Generates an audio_storage_key scoped to the user and
        conversation for Tigris upload.

        Args:
            data: ConversationCreate schema with conversation metadata.

        Returns:
            The newly created Conversation.
        """
        conversation_id = uuid_mod.uuid4()
        audio_key = f"conversations/{data.user_id}/{conversation_id}.m4a"

        location = None
        if data.latitude is not None and data.longitude is not None:
            location = WKTElement(
                f"POINT({data.longitude} {data.latitude})", srid=4326
            )

        conversation = Conversation(
            id=conversation_id,
            user_id=data.user_id,
            peer_user_id=data.peer_user_id,
            location=location,
            started_at=data.started_at,
            ended_at=data.ended_at,
            duration_seconds=data.duration_seconds,
            audio_storage_key=audio_key,
            status="pending",
        )
        self.db.add(conversation)
        await self.db.commit()
        await self.db.refresh(conversation)
        return conversation

    async def get_conversation(
        self, conversation_id: uuid_mod.UUID, user_id: uuid_mod.UUID
    ) -> Optional[Conversation]:
        """Fetch a conversation by ID, validating user ownership.

        Args:
            conversation_id: The conversation's UUID.
            user_id: The authenticated user's UUID.

        Returns:
            The Conversation if found and owned by user, None otherwise.
        """
        stmt = select(Conversation).where(
            Conversation.id == conversation_id,
            Conversation.user_id == user_id,
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def confirm_upload(
        self, conversation_id: uuid_mod.UUID, user_id: uuid_mod.UUID
    ) -> Optional[Conversation]:
        """Mark a conversation as uploaded after audio upload succeeds.

        Called after the mobile client confirms the PUT to Tigris
        completed successfully.

        Args:
            conversation_id: The conversation's UUID.
            user_id: The authenticated user's UUID.

        Returns:
            The updated Conversation, or None if not found.
        """
        conversation = await self.get_conversation(conversation_id, user_id)
        if conversation is None:
            return None

        conversation.status = "uploaded"
        await self.db.commit()
        await self.db.refresh(conversation)
        return conversation

    async def update_status(
        self, conversation_id: uuid_mod.UUID, status: str
    ) -> Optional[Conversation]:
        """Update a conversation's status field.

        Used by transcription and summarization workers to update
        processing state (e.g., transcribing, transcribed, summarizing,
        completed, failed).

        Args:
            conversation_id: The conversation's UUID.
            status: New status string.

        Returns:
            The updated Conversation, or None if not found.
        """
        stmt = select(Conversation).where(
            Conversation.id == conversation_id,
        )
        result = await self.db.execute(stmt)
        conversation = result.scalar_one_or_none()
        if conversation is None:
            return None

        conversation.status = status
        await self.db.commit()
        await self.db.refresh(conversation)
        return conversation

    async def list_conversations(
        self, user_id: uuid_mod.UUID
    ) -> list[Conversation]:
        """Get all conversations for a user ordered by most recent first.

        Args:
            user_id: The user's UUID.

        Returns:
            List of Conversation objects ordered by started_at descending.
        """
        stmt = (
            select(Conversation)
            .where(Conversation.user_id == user_id)
            .order_by(Conversation.started_at.desc())
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_conversation_detail(
        self, conversation_id: uuid_mod.UUID, user_id: uuid_mod.UUID
    ) -> Optional[dict]:
        """Fetch a conversation with its transcript and summary.

        Uses separate queries to fetch the transcript and summary
        associated with the conversation.

        Args:
            conversation_id: The conversation's UUID.
            user_id: The authenticated user's UUID.

        Returns:
            Dict with conversation, transcript, and summary data,
            or None if conversation not found.
        """
        conversation = await self.get_conversation(conversation_id, user_id)
        if conversation is None:
            return None

        # Fetch transcript
        transcript_stmt = select(Transcript).where(
            Transcript.conversation_id == conversation_id
        )
        transcript_result = await self.db.execute(transcript_stmt)
        transcript = transcript_result.scalar_one_or_none()

        # Fetch summary
        summary_stmt = select(Summary).where(
            Summary.conversation_id == conversation_id
        )
        summary_result = await self.db.execute(summary_stmt)
        summary = summary_result.scalar_one_or_none()

        return {
            "conversation": conversation,
            "transcript": transcript,
            "summary": summary,
        }

    async def get_map_conversations(
        self, user_id: uuid_mod.UUID, date: dt_mod.date
    ) -> list:
        """Fetch conversations for map display on a given date.

        Joins with the User table to retrieve peer profile info,
        extracts PostGIS coordinates via ST_X/ST_Y, and filters
        to only conversations that have GPS location data.

        Args:
            user_id: The authenticated user's UUID.
            date: The date to filter conversations by.

        Returns:
            List of Row objects with conversation and peer data.
        """
        stmt = (
            select(
                Conversation.id,
                func.ST_X(Conversation.location).label("longitude"),
                func.ST_Y(Conversation.location).label("latitude"),
                Conversation.started_at,
                Conversation.duration_seconds,
                User.display_name.label("peer_display_name"),
                User.photo_url.label("peer_photo_key"),
                User.is_anonymous.label("peer_is_anonymous"),
            )
            .outerjoin(User, Conversation.peer_user_id == User.id)
            .where(
                Conversation.user_id == user_id,
                Conversation.location.isnot(None),
                cast(Conversation.started_at, Date) == date,
            )
            .order_by(Conversation.started_at)
        )
        result = await self.db.execute(stmt)
        return result.all()

    async def get_conversation_by_id(
        self, conversation_id: uuid_mod.UUID
    ) -> Optional[Conversation]:
        """Fetch a conversation by ID without user ownership check.

        Intended for debug/admin operations where user context is
        not applicable (e.g., retranscribe endpoint).

        Args:
            conversation_id: The conversation's UUID.

        Returns:
            The Conversation if found, None otherwise.
        """
        stmt = select(Conversation).where(
            Conversation.id == conversation_id
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def delete_transcript(
        self, conversation_id: uuid_mod.UUID
    ) -> None:
        """Delete the transcript row for a conversation if it exists.

        Used during retranscribe to clear partial or stale transcripts
        before re-enqueuing the transcription task.

        Args:
            conversation_id: The conversation's UUID.
        """
        await self.db.execute(
            delete(Transcript).where(
                Transcript.conversation_id == conversation_id
            )
        )

    async def delete_summary(
        self, conversation_id: uuid_mod.UUID
    ) -> None:
        """Delete the summary row for a conversation if it exists.

        Used during retranscribe to clear stale summaries before
        re-enqueuing the summarization task.

        Args:
            conversation_id: The conversation's UUID.
        """
        await self.db.execute(
            delete(Summary).where(
                Summary.conversation_id == conversation_id
            )
        )

    async def reset_for_retranscribe(
        self, conversation: Conversation, target_status: str
    ) -> None:
        """Reset a conversation's status and clear error detail for retry.

        Updates the conversation status to the target pre-failure state
        and clears the error_detail field, then commits and refreshes.

        Args:
            conversation: The Conversation model instance.
            target_status: The status to reset to (e.g., "uploaded" or "transcribed").
        """
        conversation.status = target_status
        conversation.error_detail = None
        await self.db.commit()
        await self.db.refresh(conversation)

    async def search_conversations(
        self,
        user_id: uuid_mod.UUID,
        query: str,
        limit: int = 20,
        offset: int = 0,
    ) -> list:
        """Search conversations by keyword across transcripts, summaries, and peer names.

        Combines PostgreSQL full-text search (@@) on transcript and summary
        tsvector columns with ILIKE matching on peer display names. Results
        are ranked by FTS relevance and include ts_headline snippet highlights.

        Args:
            user_id: The authenticated user's UUID.
            query: Search query string (parsed via websearch_to_tsquery).
            limit: Maximum results to return (default 20).
            offset: Number of results to skip (default 0).

        Returns:
            List of Row objects with conversation data, peer info, snippet, and rank.
        """
        ts_query = func.websearch_to_tsquery("english", query)
        peer = aliased(User)

        # Rank: sum of transcript and summary FTS relevance scores
        rank = (
            func.coalesce(
                func.ts_rank_cd(Transcript.search_vector, ts_query), 0.0
            )
            + func.coalesce(
                func.ts_rank_cd(Summary.search_vector, ts_query), 0.0
            )
        ).label("rank")

        # Headline snippet from transcript content
        headline = func.ts_headline(
            "english",
            func.coalesce(Transcript.content, ""),
            ts_query,
            "MaxWords=50, MinWords=10, MaxFragments=2",
        ).label("snippet")

        stmt = (
            select(
                Conversation.id,
                Conversation.started_at,
                Conversation.duration_seconds,
                peer.display_name.label("peer_display_name"),
                peer.photo_url.label("peer_photo_url"),
                peer.is_anonymous.label("peer_is_anonymous"),
                headline,
                rank,
            )
            .outerjoin(
                Transcript,
                Transcript.conversation_id == Conversation.id,
            )
            .outerjoin(
                Summary,
                Summary.conversation_id == Conversation.id,
            )
            .outerjoin(
                peer,
                Conversation.peer_user_id == peer.id,
            )
            .where(
                Conversation.user_id == user_id,
                or_(
                    Transcript.search_vector.bool_op("@@")(ts_query),
                    Summary.search_vector.bool_op("@@")(ts_query),
                    peer.display_name.ilike(f"%{query}%"),
                ),
            )
            .order_by(rank.desc(), Conversation.started_at.desc())
            .limit(limit)
            .offset(offset)
        )

        result = await self.db.execute(stmt)
        return result.all()
