"""Pydantic schemas for connection request and block endpoints."""

from __future__ import annotations

import uuid
from datetime import datetime
from typing import Optional

from pydantic import BaseModel


class SocialLinkExchange(BaseModel):
    """A single social link exchanged between connected users."""

    platform: str
    handle: str

    model_config = {"from_attributes": True}


class ConnectionRequestCreate(BaseModel):
    """Request body for POST /connections/request."""

    conversation_id: uuid.UUID


class ConnectionRequestResponse(BaseModel):
    """Response schema for a connection request."""

    id: uuid.UUID
    requester_id: uuid.UUID
    recipient_id: uuid.UUID
    conversation_id: uuid.UUID
    status: str
    created_at: datetime

    model_config = {"from_attributes": True}


class AcceptResponse(BaseModel):
    """Response schema for accepting a connection request.

    Includes is_mutual flag and exchanged social links when mutual.
    """

    request: ConnectionRequestResponse
    is_mutual: bool
    exchanged_links: list[SocialLinkExchange] = []


class PendingConnectionResponse(BaseModel):
    """Response schema for a pending connection request with requester info."""

    id: uuid.UUID
    requester_id: uuid.UUID
    recipient_id: uuid.UUID
    conversation_id: uuid.UUID
    status: str
    created_at: datetime
    requester_display_name: Optional[str] = None
    requester_initials: Optional[str] = None
    requester_photo_url: Optional[str] = None
    requester_is_anonymous: bool = False


class ConnectionResponse(BaseModel):
    """Response schema for an established (mutually accepted) connection."""

    id: uuid.UUID
    peer_id: uuid.UUID
    peer_display_name: Optional[str] = None
    peer_initials: Optional[str] = None
    peer_photo_url: Optional[str] = None
    peer_is_anonymous: bool = False
    social_links: list[SocialLinkExchange] = []
    conversation_id: uuid.UUID
    connected_at: datetime

    model_config = {"from_attributes": True}


class BlockUserRequest(BaseModel):
    """Request body for POST /connections/block."""

    blocked_id: uuid.UUID


class BlockedUserResponse(BaseModel):
    """Response schema for a blocked user record."""

    id: uuid.UUID
    blocked_id: uuid.UUID
    blocked_at: datetime

    model_config = {"from_attributes": True}
