"""Upload routes for presigned URL generation."""

import logging

from botocore.exceptions import BotoCoreError, ClientError
from fastapi import APIRouter, HTTPException

from app.schemas.upload import PresignRequest, PresignResponse
from app.services.storage_service import StorageService

logger = logging.getLogger(__name__)

router = APIRouter(tags=["uploads"])


@router.post("/presign", response_model=PresignResponse)
async def create_presigned_url(body: PresignRequest) -> PresignResponse:
    """Generate a presigned URL for uploading a file to object storage.

    Accepts a key and optional content type, returns a presigned PUT URL
    that can be used directly by the client to upload a file to Tigris.

    No authentication required for Phase 1 -- auth is added in Phase 2.
    """
    try:
        service = StorageService()
        upload_url = service.generate_upload_url(
            key=body.key,
            content_type=body.content_type,
            expires_in=body.expires_in,
        )
    except (BotoCoreError, ClientError) as exc:
        logger.error("Failed to generate presigned URL: %s", exc)
        raise HTTPException(
            status_code=500,
            detail="Failed to generate presigned URL. Storage service may be unreachable.",
        ) from exc

    return PresignResponse(
        upload_url=upload_url,
        key=body.key,
        expires_in=body.expires_in,
    )
