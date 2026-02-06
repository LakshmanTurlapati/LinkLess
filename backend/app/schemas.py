"""Pydantic schemas for request/response validation."""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, EmailStr


# ─── Auth ────────────────────────────────────────────────────────────

class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    display_name: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class RefreshRequest(BaseModel):
    refresh_token: str


class AuthResponse(BaseModel):
    token: str
    refresh_token: str
    user: dict


# ─── User ────────────────────────────────────────────────────────────

class UpdateProfileRequest(BaseModel):
    display_name: Optional[str] = None
    bio: Optional[str] = None
    privacy_mode: Optional[str] = None
    social_links: Optional[dict] = None


# ─── Encounter ───────────────────────────────────────────────────────

class CreateEncounterRequest(BaseModel):
    peer_id: str
    proximity_distance: Optional[float] = None


class EncounterResponse(BaseModel):
    id: str
    user_id: str
    peer_id: str
    started_at: str
    ended_at: Optional[str] = None
    status: str
    proximity_distance: Optional[float] = None
    summary: Optional[str] = None
    topics: list[str] = []
    transcript: list[dict] = []
    peer_user: Optional[dict] = None


class EncounterListResponse(BaseModel):
    encounters: list[EncounterResponse]
    total: int
    page: int
    per_page: int
