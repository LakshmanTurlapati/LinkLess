"""Connection API routes for request lifecycle, connections list, and blocking."""

import logging
import uuid

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import get_current_user
from app.models.user import User
from app.schemas.connection import (
    AcceptResponse,
    BlockedUserResponse,
    BlockUserRequest,
    ConnectionRequestCreate,
    ConnectionRequestResponse,
    ConnectionResponse,
    SocialLinkExchange,
)
from app.services.connection_service import ConnectionService

logger = logging.getLogger(__name__)

router = APIRouter(tags=["connections"])


@router.post(
    "/request",
    response_model=ConnectionRequestResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_connection_request(
    data: ConnectionRequestCreate,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ConnectionRequestResponse:
    """Create a connection request for a conversation.

    Idempotent: returns the existing request if one already exists
    for this user and conversation.

    Raises 400 if the conversation has no identified peer.
    Raises 403 if the peer has blocked the requester.
    """
    service = ConnectionService(db)
    try:
        request = await service.create_request(user.id, data.conversation_id)
    except ValueError as exc:
        error_msg = str(exc)
        if "Cannot send connection request" in error_msg:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=error_msg,
            )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=error_msg,
        )

    return ConnectionRequestResponse.model_validate(request)


@router.post(
    "/{request_id}/accept",
    response_model=AcceptResponse,
)
async def accept_connection(
    request_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> AcceptResponse:
    """Accept a connection request.

    If mutual (both users accepted for the same conversation),
    returns exchanged social links. Otherwise returns empty links.

    Raises 404 if request not found or user is not the recipient.
    """
    service = ConnectionService(db)
    result = await service.accept_request(request_id, user.id)

    if result is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Connection request not found",
        )

    exchanged_links: list[SocialLinkExchange] = []
    if result["is_mutual"]:
        # Get the requester's shared social links for the accepting user
        req = result["request"]
        links = await service.get_exchanged_links(req.requester_id)
        exchanged_links = [
            SocialLinkExchange(platform=link.platform, handle=link.handle)
            for link in links
        ]

    return AcceptResponse(
        request=ConnectionRequestResponse.model_validate(result["request"]),
        is_mutual=result["is_mutual"],
        exchanged_links=exchanged_links,
    )


@router.post(
    "/{request_id}/decline",
    response_model=ConnectionRequestResponse,
)
async def decline_connection(
    request_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ConnectionRequestResponse:
    """Decline a connection request.

    Raises 404 if request not found or user is not the recipient.
    """
    service = ConnectionService(db)
    request = await service.decline_request(request_id, user.id)

    if request is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Connection request not found",
        )

    return ConnectionRequestResponse.model_validate(request)


@router.get(
    "",
    response_model=list[ConnectionResponse],
)
async def list_connections(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[ConnectionResponse]:
    """List all established connections with peer info and social links.

    A connection is established when both users have accepted their
    respective connection requests for the same conversation.
    """
    service = ConnectionService(db)
    connections = await service.list_connections(user.id)
    return [ConnectionResponse(**conn) for conn in connections]


@router.get(
    "/pending",
    response_model=list[ConnectionRequestResponse],
)
async def list_pending(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[ConnectionRequestResponse]:
    """List pending connection requests where the user is the recipient."""
    service = ConnectionService(db)
    requests = await service.list_pending(user.id)
    return [
        ConnectionRequestResponse.model_validate(req) for req in requests
    ]


@router.get(
    "/status",
    response_model=ConnectionRequestResponse | None,
)
async def get_connection_status(
    conversation_id: uuid.UUID = Query(
        ..., description="Conversation ID to check connection status for"
    ),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ConnectionRequestResponse | None:
    """Check connection request status for a conversation.

    Used by mobile to determine if the connect prompt should be shown.
    Returns the connection request if one exists, null otherwise.
    """
    service = ConnectionService(db)
    request = await service.get_connection_status(user.id, conversation_id)

    if request is None:
        return None

    return ConnectionRequestResponse.model_validate(request)


@router.post(
    "/block",
    response_model=BlockedUserResponse,
    status_code=status.HTTP_201_CREATED,
)
async def block_user(
    data: BlockUserRequest,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> BlockedUserResponse:
    """Block a user from proximity detection and connection requests.

    Also declines any pending connection requests between the two users.
    Idempotent: returns existing block if already blocked.
    """
    service = ConnectionService(db)
    block = await service.block_user(user.id, data.blocked_id)
    return BlockedUserResponse(
        id=block.id,
        blocked_id=block.blocked_id,
        blocked_at=block.created_at,
    )


@router.delete(
    "/block/{blocked_user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def unblock_user(
    blocked_user_id: uuid.UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Unblock a previously blocked user.

    Raises 404 if no block record exists.
    """
    service = ConnectionService(db)
    removed = await service.unblock_user(user.id, blocked_user_id)

    if not removed:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Block record not found",
        )


@router.get(
    "/blocked",
    response_model=list[BlockedUserResponse],
)
async def list_blocked(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[BlockedUserResponse]:
    """List all blocked users for local cache sync."""
    service = ConnectionService(db)
    blocked = await service.list_blocked(user.id)
    return [
        BlockedUserResponse(
            id=b.id,
            blocked_id=b.blocked_id,
            blocked_at=b.created_at,
        )
        for b in blocked
    ]
