"""Request and response schemas for conversation operations."""

import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


def _sanitize_error_message(raw: Optional[str]) -> str:
    """Strip traceback noise and truncate to a safe display length.

    Filters out lines that look like Python tracebacks (Traceback header,
    File references, and indented continuation lines). If nothing survives
    the filter, falls back to the last line of the original text. Returns
    "Unknown error" when the input is empty or None.
    """
    if not raw:
        return "Unknown error"

    lines = raw.splitlines()
    cleaned = [
        line
        for line in lines
        if not line.startswith("Traceback")
        and not line.startswith("File ")
        and not line.startswith("  ")
    ]
    result = " ".join(cleaned).strip()

    # If filtering removed everything, use the last line of the original
    if not result:
        result = lines[-1].strip() if lines else ""

    if not result:
        return "Unknown error"

    # Truncate to 300 chars
    if len(result) > 300:
        result = result[:297] + "..."

    return result


class ConversationErrorDetail(BaseModel):
    """Structured error information for a failed conversation."""

    stage: str
    status: str
    message: str
    failed_at: Optional[str] = None


def build_error_object(conversation) -> Optional[ConversationErrorDetail]:
    """Derive an error object from conversation model state.

    Returns a ConversationErrorDetail for conversations with status
    'failed' (transcription stage) or 'summarization_failed'
    (summarization stage). Returns None for all other statuses.
    """
    if conversation.status == "failed":
        return ConversationErrorDetail(
            stage="transcription",
            status=conversation.status,
            message=_sanitize_error_message(
                conversation.error_detail or ""
            ),
            failed_at=(
                conversation.updated_at.isoformat()
                if conversation.updated_at
                else None
            ),
        )
    if conversation.status == "summarization_failed":
        return ConversationErrorDetail(
            stage="summarization",
            status=conversation.status,
            message=_sanitize_error_message(
                conversation.error_detail or ""
            ),
            failed_at=(
                conversation.updated_at.isoformat()
                if conversation.updated_at
                else None
            ),
        )
    return None


class ConversationCreate(BaseModel):
    """Request body for creating a new conversation."""

    user_id: Optional[uuid.UUID] = None
    peer_user_id: Optional[uuid.UUID] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    started_at: datetime
    ended_at: Optional[datetime] = None
    duration_seconds: Optional[int] = None


class ConversationResponse(BaseModel):
    """Response body for a conversation record."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    user_id: uuid.UUID
    peer_user_id: Optional[uuid.UUID] = None
    status: str
    audio_storage_key: Optional[str] = None
    started_at: datetime
    ended_at: Optional[datetime] = None
    duration_seconds: Optional[int] = None
    created_at: datetime
    updated_at: Optional[datetime] = None
    error: Optional[ConversationErrorDetail] = None


class TranscriptResponse(BaseModel):
    """Response body for a transcript record."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    content: str
    provider: str
    language: str
    word_count: Optional[int] = None
    created_at: datetime


class SummaryResponse(BaseModel):
    """Response body for a summary record."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    content: str
    key_topics: Optional[str] = None
    provider: str
    created_at: datetime


class ConversationDetail(ConversationResponse):
    """Extended conversation response with transcript and summary."""

    transcript: Optional[TranscriptResponse] = None
    summary: Optional[SummaryResponse] = None


class UploadConfirmation(BaseModel):
    """Request body for confirming audio upload."""

    audio_storage_key: str


class AudioPresignResponse(BaseModel):
    """Response body with presigned URLs for audio upload/download."""

    upload_url: str
    audio_key: str
    download_url: str


class SearchResultResponse(BaseModel):
    """Response body for a single search result."""

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    started_at: datetime
    duration_seconds: Optional[int] = None
    peer_display_name: Optional[str] = None
    peer_photo_url: Optional[str] = None
    peer_is_anonymous: bool = False
    snippet: Optional[str] = None
    rank: float = 0.0


class MapConversationResponse(BaseModel):
    """Response body for a conversation formatted for map display.

    Contains extracted GPS coordinates, peer profile info with
    anonymous masking, and basic conversation metadata for
    rendering map pins.
    """

    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    latitude: float
    longitude: float
    started_at: datetime
    duration_seconds: Optional[int] = None
    peer_display_name: Optional[str] = None
    peer_initials: Optional[str] = None
    peer_photo_url: Optional[str] = None
    peer_is_anonymous: bool = False
