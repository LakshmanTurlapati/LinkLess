"""Schemas for debug-only API endpoints."""

from pydantic import BaseModel, Field


class ChatRequest(BaseModel):
    """Request body for the debug chat endpoint."""

    message: str = Field(
        ...,
        min_length=1,
        max_length=2000,
        description="User message to send to the AI",
    )
