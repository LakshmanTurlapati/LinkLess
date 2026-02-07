"""Conversation business logic for CRUD operations and status management."""

import logging
import uuid as uuid_mod
from typing import Optional

from geoalchemy2 import WKTElement
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.conversation import Conversation, Summary, Transcript
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
        audio_key = f"conversations/{data.user_id}/{conversation_id}.aac"

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
