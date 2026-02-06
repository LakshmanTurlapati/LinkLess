"""Authentication endpoints — register, login, refresh, logout."""

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.database import get_db
from app.models import User
from app.schemas import RegisterRequest, LoginRequest, RefreshRequest, AuthResponse
from app.auth_utils import (
    hash_password,
    verify_password,
    create_access_token,
    create_refresh_token,
    decode_token,
    get_current_user,
)

router = APIRouter()


@router.post("/register", response_model=AuthResponse)
async def register(request: RegisterRequest, db: AsyncSession = Depends(get_db)):
    """Register a new user account."""
    # Check if email already exists
    result = await db.execute(select(User).where(User.email == request.email))
    if result.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="Email already registered",
        )

    user = User(
        email=request.email,
        password_hash=hash_password(request.password),
        display_name=request.display_name,
    )
    db.add(user)
    await db.flush()

    token = create_access_token(user.id)
    refresh = create_refresh_token(user.id)

    return AuthResponse(
        token=token,
        refresh_token=refresh,
        user=user.to_dict(include_email=True),
    )


@router.post("/login", response_model=AuthResponse)
async def login(request: LoginRequest, db: AsyncSession = Depends(get_db)):
    """Log in with email and password."""
    result = await db.execute(select(User).where(User.email == request.email))
    user = result.scalar_one_or_none()

    if not user or not verify_password(request.password, user.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid email or password",
        )

    token = create_access_token(user.id)
    refresh = create_refresh_token(user.id)

    return AuthResponse(
        token=token,
        refresh_token=refresh,
        user=user.to_dict(include_email=True),
    )


@router.post("/refresh", response_model=AuthResponse)
async def refresh_token(request: RefreshRequest, db: AsyncSession = Depends(get_db)):
    """Refresh an expired access token."""
    payload = decode_token(request.refresh_token)

    if payload is None or payload.get("type") != "refresh":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid refresh token",
        )

    user_id = payload.get("sub")
    result = await db.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )

    token = create_access_token(user.id)
    refresh = create_refresh_token(user.id)

    return AuthResponse(
        token=token,
        refresh_token=refresh,
        user=user.to_dict(include_email=True),
    )


@router.post("/logout")
async def logout(current_user: User = Depends(get_current_user)):
    """Log out the current user (client should discard tokens)."""
    return {"message": "Logged out successfully"}
