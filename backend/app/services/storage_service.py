"""Tigris/S3-compatible object storage service for presigned URL generation.

Supports both audio file uploads (Phase 5/6) and profile photo uploads (Phase 3).
Designed to be reusable across any file type that needs presigned URL upload.
"""

import logging
import uuid

import boto3
from botocore.config import Config

from app.core.config import settings

logger = logging.getLogger(__name__)


class StorageService:
    """Wraps boto3 S3 client with Tigris-compatible configuration.

    Generates presigned URLs for uploading and downloading files
    from Tigris object storage (S3-compatible API).

    IMPORTANT: boto3 must be pinned to <=1.35.95. Versions 1.36.0+
    break uploads to Tigris with MissingContentLength error.
    """

    def __init__(self) -> None:
        self._client = boto3.client(
            "s3",
            endpoint_url=settings.tigris_endpoint,
            aws_access_key_id=settings.aws_access_key_id,
            aws_secret_access_key=settings.aws_secret_access_key,
            config=Config(
                s3={"addressing_style": "virtual"},
                signature_version="s3v4",
            ),
        )
        self._bucket = settings.tigris_bucket

    def generate_upload_url(
        self,
        key: str,
        content_type: str = "audio/aac",
        expires_in: int = 3600,
    ) -> str:
        """Generate a presigned URL for uploading an object.

        Args:
            key: The S3 object key (path) for the upload.
            content_type: MIME type of the file being uploaded.
            expires_in: URL expiration time in seconds.

        Returns:
            A presigned URL string for PUT upload.
        """
        url: str = self._client.generate_presigned_url(
            "put_object",
            Params={
                "Bucket": self._bucket,
                "Key": key,
                "ContentType": content_type,
            },
            ExpiresIn=expires_in,
        )
        return url

    def generate_download_url(
        self,
        key: str,
        expires_in: int = 3600,
    ) -> str:
        """Generate a presigned URL for downloading an object.

        Args:
            key: The S3 object key (path) to download.
            expires_in: URL expiration time in seconds.

        Returns:
            A presigned URL string for GET download.
        """
        url: str = self._client.generate_presigned_url(
            "get_object",
            Params={
                "Bucket": self._bucket,
                "Key": key,
            },
            ExpiresIn=expires_in,
        )
        return url

    def generate_presigned_upload_url(
        self,
        user_id: str,
        content_type: str = "image/jpeg",
    ) -> dict:
        """Generate a presigned URL for profile photo upload.

        Creates a unique key under profiles/{user_id}/ and returns
        both the upload URL and the object key for storage in the
        user record.

        Args:
            user_id: The user's UUID string.
            content_type: MIME type of the image (default image/jpeg).

        Returns:
            Dict with 'upload_url' (presigned PUT URL) and
            'photo_key' (object key to store in DB).
        """
        key = f"profiles/{user_id}/{uuid.uuid4()}.jpg"
        url = self.generate_upload_url(
            key=key,
            content_type=content_type,
            expires_in=300,  # 5 minutes for photo uploads
        )
        return {"upload_url": url, "photo_key": key}

    def get_public_url(self, key: str) -> str:
        """Construct a public URL for an object stored in the bucket.

        Uses the Tigris public URL pattern: https://{bucket}.t3.storage.dev/{key}

        Args:
            key: The S3 object key.

        Returns:
            The full public URL for the object.
        """
        return f"https://{self._bucket}.fly.storage.tigris.dev/{key}"
