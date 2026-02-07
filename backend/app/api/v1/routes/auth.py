"""Authentication API routes for OTP, token management, and logout."""

from fastapi import APIRouter, Depends, HTTPException, Response, status

from app.core.dependencies import get_auth_service, get_current_user
from app.models.user import User
from app.schemas.auth import (
    AuthTokenResponse,
    RefreshTokenRequest,
    SendOtpRequest,
    SendOtpResponse,
    UserResponse,
    VerifyOtpRequest,
)
from app.services.auth_service import (
    AuthService,
    TwilioApiError,
    TwilioRateLimitError,
)

router = APIRouter(prefix="/auth", tags=["auth"])


def _mask_phone(phone: str) -> str:
    """Mask a phone number, showing only the last 4 digits.

    Example: +12345678900 -> ****8900
    """
    if len(phone) <= 4:
        return "****"
    return "*" * (len(phone) - 4) + phone[-4:]


@router.post("/send-otp", response_model=SendOtpResponse)
async def send_otp(
    body: SendOtpRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> SendOtpResponse:
    """Send an OTP code to the given phone number via SMS."""
    try:
        await auth_service.send_otp(body.phone_number)
    except TwilioRateLimitError:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many OTP requests. Please wait before trying again.",
        )
    except TwilioApiError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to send OTP: {exc.detail}",
        )

    return SendOtpResponse(
        message="OTP sent successfully",
        masked_phone=_mask_phone(body.phone_number),
    )


@router.post("/verify-otp", response_model=AuthTokenResponse)
async def verify_otp(
    body: VerifyOtpRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> AuthTokenResponse:
    """Verify an OTP code and return access/refresh tokens.

    Creates a new user if this phone number has not been seen before.
    """
    is_valid = await auth_service.verify_otp(body.phone_number, body.code)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired OTP code",
        )

    user = await auth_service.get_or_create_user(body.phone_number)
    session = await auth_service.create_session(str(user.id))
    session.user = UserResponse.from_model(user)
    return session


@router.post("/refresh", response_model=AuthTokenResponse)
async def refresh_token(
    body: RefreshTokenRequest,
    auth_service: AuthService = Depends(get_auth_service),
) -> AuthTokenResponse:
    """Exchange a valid refresh token for a new access/refresh token pair."""
    result = await auth_service.refresh_session(body.refresh_token)
    if result is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired refresh token",
        )
    return result


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(
    current_user: User = Depends(get_current_user),
    auth_service: AuthService = Depends(get_auth_service),
) -> Response:
    """Revoke all refresh tokens for the authenticated user."""
    await auth_service.revoke_user_sessions(str(current_user.id))
    return Response(status_code=status.HTTP_204_NO_CONTENT)
