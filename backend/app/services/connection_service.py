"""Connection business logic for request lifecycle, mutual-accept, and blocking."""

import logging
import uuid as uuid_mod
from typing import Optional

from sqlalchemy import and_, delete, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.blocked_user import BlockedUser
from app.models.connection_request import ConnectionRequest
from app.models.conversation import Conversation
from app.models.social_link import SocialLink
from app.models.user import User
from app.services.storage_service import StorageService

logger = logging.getLogger(__name__)


class ConnectionService:
    """Handles connection request lifecycle, mutual-accept logic, and blocking.

    The mutual-accept pattern works as follows:
    - Each user sends a separate ConnectionRequest for a conversation
    - When both requests are accepted, social links (is_shared=True) are exchanged
    - A connection is "established" only when both sides have accepted
    """

    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def create_request(
        self,
        requester_id: uuid_mod.UUID,
        conversation_id: uuid_mod.UUID,
    ) -> ConnectionRequest:
        """Create a connection request for a conversation.

        Idempotent: returns existing request if one already exists for
        (requester_id, conversation_id).

        Args:
            requester_id: The user sending the request.
            conversation_id: The conversation triggering the request.

        Returns:
            The created or existing ConnectionRequest.

        Raises:
            ValueError: If conversation has no peer, or if the peer has
                blocked the requester.
        """
        # Look up the conversation to get the peer
        conv_stmt = select(Conversation).where(
            Conversation.id == conversation_id,
        )
        conv_result = await self.db.execute(conv_stmt)
        conversation = conv_result.scalar_one_or_none()

        if conversation is None:
            raise ValueError("Conversation not found")

        # Determine the peer: the requester could be either user_id or peer_user_id
        if conversation.user_id == requester_id:
            peer_id = conversation.peer_user_id
        elif conversation.peer_user_id == requester_id:
            peer_id = conversation.user_id
        else:
            raise ValueError("User is not a participant in this conversation")

        if peer_id is None:
            raise ValueError("Conversation has no identified peer")

        # Check for existing request (idempotent)
        existing_stmt = select(ConnectionRequest).where(
            ConnectionRequest.requester_id == requester_id,
            ConnectionRequest.conversation_id == conversation_id,
        )
        existing_result = await self.db.execute(existing_stmt)
        existing = existing_result.scalar_one_or_none()
        if existing is not None:
            return existing

        # Check if the peer has blocked the requester
        block_stmt = select(BlockedUser).where(
            BlockedUser.blocker_id == peer_id,
            BlockedUser.blocked_id == requester_id,
        )
        block_result = await self.db.execute(block_stmt)
        if block_result.scalar_one_or_none() is not None:
            raise ValueError("Cannot send connection request")

        # Create the request
        request = ConnectionRequest(
            id=uuid_mod.uuid4(),
            requester_id=requester_id,
            recipient_id=peer_id,
            conversation_id=conversation_id,
            status="pending",
        )
        self.db.add(request)
        await self.db.commit()
        await self.db.refresh(request)
        return request

    async def accept_request(
        self,
        request_id: uuid_mod.UUID,
        user_id: uuid_mod.UUID,
    ) -> Optional[dict]:
        """Accept a connection request.

        After accepting, checks if the peer has also accepted their
        request for the same conversation (mutual acceptance).

        Args:
            request_id: The connection request to accept.
            user_id: The authenticated user (must be the recipient).

        Returns:
            Dict with 'request' and 'is_mutual' flag, or None if not
            found or unauthorized.
        """
        stmt = select(ConnectionRequest).where(
            ConnectionRequest.id == request_id,
        )
        result = await self.db.execute(stmt)
        request = result.scalar_one_or_none()

        if request is None or request.recipient_id != user_id:
            return None

        request.status = "accepted"
        await self.db.commit()
        await self.db.refresh(request)

        # Check for mutual acceptance:
        # The peer's request where peer is the requester for the same conversation
        mutual_stmt = select(ConnectionRequest).where(
            ConnectionRequest.requester_id == request.recipient_id,
            ConnectionRequest.conversation_id == request.conversation_id,
            ConnectionRequest.status == "accepted",
        )
        mutual_result = await self.db.execute(mutual_stmt)
        peer_request = mutual_result.scalar_one_or_none()

        is_mutual = peer_request is not None

        return {"request": request, "is_mutual": is_mutual}

    async def decline_request(
        self,
        request_id: uuid_mod.UUID,
        user_id: uuid_mod.UUID,
    ) -> Optional[ConnectionRequest]:
        """Decline a connection request.

        Args:
            request_id: The connection request to decline.
            user_id: The authenticated user (must be the recipient).

        Returns:
            The updated ConnectionRequest, or None if not found.
        """
        stmt = select(ConnectionRequest).where(
            ConnectionRequest.id == request_id,
        )
        result = await self.db.execute(stmt)
        request = result.scalar_one_or_none()

        if request is None or request.recipient_id != user_id:
            return None

        request.status = "declined"
        await self.db.commit()
        await self.db.refresh(request)
        return request

    async def get_exchanged_links(
        self, peer_id: uuid_mod.UUID
    ) -> list[SocialLink]:
        """Get a peer's shared social links for exchange.

        Only returns links where is_shared=True, per Phase 3 design.

        Args:
            peer_id: The peer whose shared links to retrieve.

        Returns:
            List of SocialLink objects with is_shared=True.
        """
        stmt = select(SocialLink).where(
            SocialLink.user_id == peer_id,
            SocialLink.is_shared == True,  # noqa: E712
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def list_connections(
        self, user_id: uuid_mod.UUID
    ) -> list[dict]:
        """List all established (mutually accepted) connections.

        A connection is established when:
        1. The user has sent a request that is accepted
        2. The peer has also sent a request for the same conversation
           that is accepted

        Returns peer profile info and exchanged social links.

        Args:
            user_id: The authenticated user.

        Returns:
            List of dicts with peer info and social links.
        """
        # Get all requests where user is the requester and status is accepted
        user_requests_stmt = select(ConnectionRequest).where(
            ConnectionRequest.requester_id == user_id,
            ConnectionRequest.status == "accepted",
        )
        user_requests_result = await self.db.execute(user_requests_stmt)
        user_requests = list(user_requests_result.scalars().all())

        connections = []
        storage = StorageService()

        for req in user_requests:
            # Check if the peer also accepted for the same conversation
            peer_req_stmt = select(ConnectionRequest).where(
                ConnectionRequest.requester_id == req.recipient_id,
                ConnectionRequest.conversation_id == req.conversation_id,
                ConnectionRequest.status == "accepted",
            )
            peer_req_result = await self.db.execute(peer_req_stmt)
            peer_req = peer_req_result.scalar_one_or_none()

            if peer_req is None:
                continue  # Not mutual yet

            # Get peer user info
            peer_stmt = select(User).where(User.id == req.recipient_id)
            peer_result = await self.db.execute(peer_stmt)
            peer = peer_result.scalar_one_or_none()

            if peer is None:
                continue

            # Apply anonymous masking (same pattern as ProfileResponse.from_user)
            peer_display_name: Optional[str] = None
            peer_initials: Optional[str] = None

            if peer.display_name:
                parts = peer.display_name.strip().split()
                peer_initials = "".join(p[0].upper() for p in parts[:2])
                if not peer.is_anonymous:
                    peer_display_name = peer.display_name

            # Photo URL from key
            peer_photo_url: Optional[str] = None
            if peer.photo_url:
                peer_photo_url = storage.get_public_url(peer.photo_url)

            # Get exchanged social links
            shared_links = await self.get_exchanged_links(req.recipient_id)

            connections.append(
                {
                    "id": req.id,
                    "peer_id": req.recipient_id,
                    "peer_display_name": peer_display_name,
                    "peer_initials": peer_initials,
                    "peer_photo_url": peer_photo_url,
                    "peer_is_anonymous": peer.is_anonymous,
                    "social_links": [
                        {"platform": link.platform, "handle": link.handle}
                        for link in shared_links
                    ],
                    "conversation_id": req.conversation_id,
                    "connected_at": req.updated_at,
                }
            )

        return connections

    async def list_pending(
        self, user_id: uuid_mod.UUID
    ) -> list[ConnectionRequest]:
        """List pending connection requests where user is the recipient.

        Args:
            user_id: The authenticated user.

        Returns:
            List of pending ConnectionRequest objects.
        """
        stmt = select(ConnectionRequest).where(
            ConnectionRequest.recipient_id == user_id,
            ConnectionRequest.status == "pending",
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_connection_status(
        self,
        user_id: uuid_mod.UUID,
        conversation_id: uuid_mod.UUID,
    ) -> Optional[ConnectionRequest]:
        """Check if a connection request exists for a conversation.

        Used by mobile to determine if the connect prompt should be shown.

        Args:
            user_id: The authenticated user.
            conversation_id: The conversation to check.

        Returns:
            The ConnectionRequest if one exists, None otherwise.
        """
        stmt = select(ConnectionRequest).where(
            or_(
                ConnectionRequest.requester_id == user_id,
                ConnectionRequest.recipient_id == user_id,
            ),
            ConnectionRequest.conversation_id == conversation_id,
        )
        result = await self.db.execute(stmt)
        return result.scalars().first()

    async def block_user(
        self,
        blocker_id: uuid_mod.UUID,
        blocked_id: uuid_mod.UUID,
    ) -> BlockedUser:
        """Block a user from proximity detection and connection requests.

        Also declines any pending connection requests between the two users.

        Args:
            blocker_id: The user doing the blocking.
            blocked_id: The user being blocked.

        Returns:
            The BlockedUser record.
        """
        # Check for existing block
        existing_stmt = select(BlockedUser).where(
            BlockedUser.blocker_id == blocker_id,
            BlockedUser.blocked_id == blocked_id,
        )
        existing_result = await self.db.execute(existing_stmt)
        existing = existing_result.scalar_one_or_none()
        if existing is not None:
            return existing

        # Create block record
        block = BlockedUser(
            id=uuid_mod.uuid4(),
            blocker_id=blocker_id,
            blocked_id=blocked_id,
        )
        self.db.add(block)

        # Decline any pending connection requests between the two users
        pending_stmt = select(ConnectionRequest).where(
            ConnectionRequest.status == "pending",
            or_(
                and_(
                    ConnectionRequest.requester_id == blocker_id,
                    ConnectionRequest.recipient_id == blocked_id,
                ),
                and_(
                    ConnectionRequest.requester_id == blocked_id,
                    ConnectionRequest.recipient_id == blocker_id,
                ),
            ),
        )
        pending_result = await self.db.execute(pending_stmt)
        pending_requests = pending_result.scalars().all()
        for req in pending_requests:
            req.status = "declined"

        await self.db.commit()
        await self.db.refresh(block)
        return block

    async def unblock_user(
        self,
        blocker_id: uuid_mod.UUID,
        blocked_id: uuid_mod.UUID,
    ) -> bool:
        """Remove a block on a user.

        Args:
            blocker_id: The user who blocked.
            blocked_id: The user who was blocked.

        Returns:
            True if a block was removed, False if none existed.
        """
        stmt = delete(BlockedUser).where(
            BlockedUser.blocker_id == blocker_id,
            BlockedUser.blocked_id == blocked_id,
        )
        result = await self.db.execute(stmt)
        await self.db.commit()
        return result.rowcount > 0

    async def list_blocked(
        self, user_id: uuid_mod.UUID
    ) -> list[BlockedUser]:
        """List all users blocked by the given user.

        Args:
            user_id: The authenticated user.

        Returns:
            List of BlockedUser records.
        """
        stmt = select(BlockedUser).where(
            BlockedUser.blocker_id == user_id,
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())
