"""JWT token creation, decoding, and hashing utilities.

Uses PyJWT with HS256 for token signing. Refresh tokens are stored
as SHA-256 hashes in the database, never in plaintext.
"""

import hashlib
import uuid
from datetime import UTC, datetime, timedelta

import jwt

from app.core.config import settings


class TokenExpiredError(Exception):
    """Raised when a JWT token has expired."""

    pass


class TokenInvalidError(Exception):
    """Raised when a JWT token is malformed or signature is invalid."""

    pass


def create_access_token(user_id: str) -> str:
    """Create a short-lived JWT access token.

    Args:
        user_id: The user's UUID as a string.

    Returns:
        Encoded JWT string.
    """
    now = datetime.now(UTC)
    payload = {
        "sub": user_id,
        "type": "access",
        "iat": now,
        "exp": now + timedelta(minutes=settings.access_token_expire_minutes),
    }
    return jwt.encode(payload, settings.jwt_secret_key, algorithm="HS256")


def create_refresh_token(user_id: str) -> tuple[str, str]:
    """Create a long-lived JWT refresh token and its SHA-256 hash.

    Args:
        user_id: The user's UUID as a string.

    Returns:
        Tuple of (raw_token, token_hash). The hash is stored in the DB;
        the raw token is returned to the client.
    """
    now = datetime.now(UTC)
    payload = {
        "sub": user_id,
        "type": "refresh",
        "jti": str(uuid.uuid4()),
        "iat": now,
        "exp": now + timedelta(days=settings.refresh_token_expire_days),
    }
    raw_token = jwt.encode(
        payload, settings.jwt_secret_key, algorithm="HS256"
    )
    return raw_token, hash_token(raw_token)


def decode_token(token: str) -> dict:
    """Decode and validate a JWT token.

    Args:
        token: The encoded JWT string.

    Returns:
        Decoded payload dictionary.

    Raises:
        TokenExpiredError: If the token has expired.
        TokenInvalidError: If the token is malformed or signature is invalid.
    """
    try:
        return jwt.decode(
            token, settings.jwt_secret_key, algorithms=["HS256"]
        )
    except jwt.ExpiredSignatureError:
        raise TokenExpiredError("Token has expired")
    except jwt.InvalidTokenError as exc:
        raise TokenInvalidError(f"Invalid token: {exc}")


def hash_token(token: str) -> str:
    """Compute SHA-256 hex digest of a token string.

    Args:
        token: Raw token string.

    Returns:
        64-character hexadecimal hash string.
    """
    return hashlib.sha256(token.encode("utf-8")).hexdigest()
