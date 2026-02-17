"""Request and response schemas for conversation operations."""

import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel, ConfigDict


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
