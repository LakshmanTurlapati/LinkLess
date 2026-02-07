"""Request and response schemas for presigned URL operations."""

from pydantic import BaseModel, Field


class PresignRequest(BaseModel):
    """Request body for generating a presigned upload URL."""

    key: str = Field(
        ...,
        description="S3 object key (path) for the upload",
        min_length=1,
        max_length=1024,
    )
    content_type: str = Field(
        default="audio/aac",
        description="MIME type of the file being uploaded",
    )
    expires_in: int = Field(
        default=3600,
        ge=60,
        le=86400,
        description="URL expiration time in seconds (60-86400)",
    )


class PresignResponse(BaseModel):
    """Response body containing the presigned upload URL."""

    upload_url: str = Field(
        ...,
        description="Presigned URL for uploading the file via PUT",
    )
    key: str = Field(
        ...,
        description="S3 object key that was used",
    )
    expires_in: int = Field(
        ...,
        description="URL expiration time in seconds",
    )
