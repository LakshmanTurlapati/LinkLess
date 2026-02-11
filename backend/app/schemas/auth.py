"""Pydantic schemas for authentication endpoints."""

from __future__ import annotations

import re

from pydantic import BaseModel, field_validator


_E164_REGEX = re.compile(r"^\+[1-9]\d{1,14}$")
_OTP_CODE_REGEX = re.compile(r"^\d{4,10}$")


class SendOtpRequest(BaseModel):
    """Request body for POST /auth/send-otp."""

    phone_number: str

    @field_validator("phone_number")
    @classmethod
    def validate_e164(cls, v: str) -> str:
        if not _E164_REGEX.match(v):
            raise ValueError(
                "Phone number must be in E.164 format (e.g. +12345678900)"
            )
        return v


class SendOtpResponse(BaseModel):
    """Response for POST /auth/send-otp."""

    message: str
    masked_phone: str


class VerifyOtpRequest(BaseModel):
    """Request body for POST /auth/verify-otp."""

    phone_number: str
    code: str

    @field_validator("phone_number")
    @classmethod
    def validate_e164(cls, v: str) -> str:
        if not _E164_REGEX.match(v):
            raise ValueError(
                "Phone number must be in E.164 format (e.g. +12345678900)"
            )
        return v

    @field_validator("code")
    @classmethod
    def validate_code(cls, v: str) -> str:
        if not _OTP_CODE_REGEX.match(v):
            raise ValueError("OTP code must be 4-10 digits")
        return v


class RefreshTokenRequest(BaseModel):
    """Request body for POST /auth/refresh."""

    refresh_token: str


class UserResponse(BaseModel):
    """Serialized user object returned in auth responses."""

    id: str
    phone_number: str

    @classmethod
    def from_model(cls, user: object) -> UserResponse:
        """Create UserResponse from a User ORM model."""
        return cls(
            id=str(user.id),  # type: ignore[attr-defined]
            phone_number=user.phone_number,  # type: ignore[attr-defined]
        )


class AuthTokenResponse(BaseModel):
    """Response containing access and refresh tokens."""

    access_token: str
    refresh_token: str
    user: UserResponse | None = None
    is_new_user: bool = False
