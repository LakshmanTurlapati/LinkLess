"""Conversation API routes for lifecycle management and audio upload."""

import logging
import uuid

from botocore.exceptions import BotoCoreError, ClientError
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.schemas.conversation import (
    AudioPresignResponse,
    ConversationCreate,
    ConversationDetail,
    ConversationResponse,
    SummaryResponse,
    TranscriptResponse,
)
from app.services.conversation_service import ConversationService
from app.services.storage_service import StorageService

logger = logging.getLogger(__name__)

router = APIRouter(tags=["conversations"])


@router.post(
    "",
    response_model=dict,
    status_code=status.HTTP_201_CREATED,
)
async def create_conversation(
    data: ConversationCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """Create a new conversation and return presigned upload URL.

    Overrides user_id in the request body with the authenticated
    user's ID. Generates a presigned upload URL for audio file
    storage and a download URL for later transcription access.

    Returns both the conversation record and the audio upload URLs.
    """
    # Override user_id with authenticated user
    data.user_id = user.id

    service = ConversationService(db)
    conversation = await service.create_conversation(data)

    # Generate presigned URLs for audio upload and download
    try:
        storage = StorageService()
        upload_url = storage.generate_upload_url(
            key=conversation.audio_storage_key,
            content_type="audio/aac",
            expires_in=3600,
        )
        download_url = storage.generate_download_url(
            key=conversation.audio_storage_key,
            expires_in=3600,
        )
    except (BotoCoreError, ClientError) as exc:
        logger.error("Failed to generate presigned URLs: %s", exc)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="Failed to generate upload URL. Storage service may be unreachable.",
        ) from exc

    return {
        "conversation": ConversationResponse.model_validate(conversation),
        "upload": AudioPresignResponse(
            upload_url=upload_url,
            audio_key=conversation.audio_storage_key,
            download_url=download_url,
        ),
    }


@router.post(
    "/{conversation_id}/confirm-upload",
    response_model=ConversationResponse,
)
async def confirm_upload(
    conversation_id: uuid.UUID,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ConversationResponse:
    """Confirm that audio upload to Tigris completed successfully.

    Updates conversation status to 'uploaded' and enqueues a
    transcription job via ARQ for async processing.

    Raises 404 if conversation not found or not owned by user.
    """
    service = ConversationService(db)
    conversation = await service.confirm_upload(conversation_id, user.id)

    if conversation is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    # Enqueue transcription job via ARQ
    arq_pool = getattr(request.app.state, "arq_pool", None)
    if arq_pool is not None:
        try:
            await arq_pool.enqueue_job(
                "transcribe_conversation",
                conversation_id=str(conversation_id),
            )
            logger.info(
                "Enqueued transcription job for conversation %s",
                conversation_id,
            )
        except Exception as exc:
            # Log but don't fail the request -- transcription can be retried
            logger.error(
                "Failed to enqueue transcription job for %s: %s",
                conversation_id,
                exc,
            )
    else:
        logger.warning(
            "ARQ pool not available, skipping transcription enqueue for %s",
            conversation_id,
        )

    return ConversationResponse.model_validate(conversation)


@router.get(
    "",
    response_model=list[ConversationResponse],
)
async def list_conversations(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[ConversationResponse]:
    """List all conversations for the authenticated user.

    Returns conversations ordered by most recent first.
    """
    service = ConversationService(db)
    conversations = await service.list_conversations(user.id)
    return [
        ConversationResponse.model_validate(conv) for conv in conversations
    ]


@router.get(
    "/{conversation_id}",
    response_model=ConversationDetail,
)
async def get_conversation(
    conversation_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ConversationDetail:
    """Get conversation details with transcript and summary.

    Returns the full conversation record along with its transcript
    and summary if they have been generated.

    Raises 404 if conversation not found or not owned by user.
    """
    service = ConversationService(db)
    detail = await service.get_conversation_detail(conversation_id, user.id)

    if detail is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Conversation not found",
        )

    conversation = detail["conversation"]
    transcript = detail["transcript"]
    summary = detail["summary"]

    result = ConversationDetail.model_validate(conversation)

    if transcript is not None:
        result.transcript = TranscriptResponse.model_validate(transcript)
    if summary is not None:
        result.summary = SummaryResponse.model_validate(summary)

    return result
