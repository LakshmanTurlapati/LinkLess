"""Authentication service for OTP verification and session management.

Integrates with Twilio Verify API for SMS OTP delivery and validation.
Manages JWT access/refresh token issuance and refresh token rotation.
"""

from datetime import UTC, datetime, timedelta

import httpx
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.core.security import (
    TokenExpiredError,
    TokenInvalidError,
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_token,
)
from app.models.refresh_token import RefreshToken
from app.models.user import User
from app.schemas.auth import AuthTokenResponse, UserResponse


class TwilioRateLimitError(Exception):
    """Raised when Twilio returns a 429 rate limit response."""

    pass


class TwilioApiError(Exception):
    """Raised when Twilio returns a non-2xx, non-429 response."""

    def __init__(self, status_code: int, detail: str) -> None:
        self.status_code = status_code
        self.detail = detail
        super().__init__(f"Twilio API error {status_code}: {detail}")


class AuthService:
    """Handles OTP verification, user creation, and token management."""

    def __init__(self, db: AsyncSession) -> None:
        self.db = db

    async def send_otp(self, phone_number: str) -> None:
        """Send an OTP to the given phone number via Twilio Verify.

        In test mode, this is a no-op.

        Args:
            phone_number: E.164 formatted phone number.

        Raises:
            TwilioRateLimitError: If Twilio returns 429.
            TwilioApiError: If Twilio returns any other non-2xx status.
        """
        if settings.twilio_test_mode:
            return

        url = (
            f"https://verify.twilio.com/v2/Services/"
            f"{settings.twilio_verify_service_sid}/Verifications"
        )
        async with httpx.AsyncClient() as client:
            response = await client.post(
                url,
                data={"To": phone_number, "Channel": "sms"},
                auth=(
                    settings.twilio_account_sid,
                    settings.twilio_auth_token,
                ),
            )

        if response.status_code == 429:
            raise TwilioRateLimitError(
                "Too many OTP requests. Please wait before trying again."
            )

        if response.status_code >= 400:
            detail = response.text
            try:
                body = response.json()
                detail = body.get("message", detail)
            except Exception:
                pass
            raise TwilioApiError(response.status_code, detail)

    async def verify_otp(self, phone_number: str, code: str) -> bool:
        """Verify an OTP code via Twilio Verify.

        In test mode, accepts "123456" as the valid code.

        Args:
            phone_number: E.164 formatted phone number.
            code: The OTP code entered by the user.

        Returns:
            True if the code is valid, False otherwise.
        """
        if settings.twilio_test_mode:
            return code == "123456"

        url = (
            f"https://verify.twilio.com/v2/Services/"
            f"{settings.twilio_verify_service_sid}/VerificationCheck"
        )
        async with httpx.AsyncClient() as client:
            response = await client.post(
                url,
                data={"To": phone_number, "Code": code},
                auth=(
                    settings.twilio_account_sid,
                    settings.twilio_auth_token,
                ),
            )

        if response.status_code == 404:
            # Verification expired or not found
            return False

        if response.status_code >= 400:
            return False

        body = response.json()
        return body.get("status") == "approved"

    async def get_or_create_user(self, phone_number: str) -> User:
        """Find an existing user by phone number or create a new one.

        Args:
            phone_number: E.164 formatted phone number.

        Returns:
            The existing or newly created User.
        """
        stmt = select(User).where(User.phone_number == phone_number)
        result = await self.db.execute(stmt)
        user = result.scalar_one_or_none()

        if user is not None:
            return user

        user = User(phone_number=phone_number)
        self.db.add(user)
        await self.db.commit()
        await self.db.refresh(user)
        return user

    async def create_session(self, user_id: str) -> AuthTokenResponse:
        """Create a new access/refresh token pair for a user.

        The refresh token hash is stored in the database; the raw token
        is returned to the client.

        Args:
            user_id: The user's UUID as a string.

        Returns:
            AuthTokenResponse with access_token and refresh_token.
        """
        access_token = create_access_token(user_id)
        raw_refresh, token_hash = create_refresh_token(user_id)

        refresh_record = RefreshToken(
            user_id=user_id,
            token_hash=token_hash,
            expires_at=datetime.now(UTC)
            + timedelta(days=settings.refresh_token_expire_days),
        )
        self.db.add(refresh_record)
        await self.db.commit()

        return AuthTokenResponse(
            access_token=access_token,
            refresh_token=raw_refresh,
        )

    async def refresh_session(
        self, raw_refresh_token: str
    ) -> AuthTokenResponse | None:
        """Exchange a valid refresh token for a new token pair.

        Implements refresh token rotation: the old token is revoked
        and a new pair is issued.

        Args:
            raw_refresh_token: The raw refresh token JWT from the client.

        Returns:
            New AuthTokenResponse if valid, None if token is
            expired, invalid, or revoked.
        """
        try:
            payload = decode_token(raw_refresh_token)
        except (TokenExpiredError, TokenInvalidError):
            return None

        if payload.get("type") != "refresh":
            return None

        token_hash = hash_token(raw_refresh_token)
        stmt = select(RefreshToken).where(
            RefreshToken.token_hash == token_hash,
            RefreshToken.revoked == False,  # noqa: E712
        )
        result = await self.db.execute(stmt)
        existing = result.scalar_one_or_none()

        if existing is None:
            return None

        # Revoke the old refresh token
        existing.revoked = True
        await self.db.flush()

        # Issue new token pair
        user_id = payload["sub"]
        new_session = await self.create_session(user_id)
        return new_session

    async def revoke_user_sessions(self, user_id: str) -> None:
        """Revoke all active refresh tokens for a user (logout).

        Args:
            user_id: The user's UUID as a string.
        """
        stmt = (
            update(RefreshToken)
            .where(
                RefreshToken.user_id == user_id,
                RefreshToken.revoked == False,  # noqa: E712
            )
            .values(revoked=True)
        )
        await self.db.execute(stmt)
        await self.db.commit()
