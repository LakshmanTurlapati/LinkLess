"""Tigris/S3-compatible object storage service for presigned URL generation."""

import logging

import boto3
from botocore.config import Config

from app.core.config import settings

logger = logging.getLogger(__name__)


class StorageService:
    """Wraps boto3 S3 client with Tigris-compatible configuration.

    Generates presigned URLs for uploading and downloading audio files
    from Tigris object storage (S3-compatible API).
    """

    def __init__(self) -> None:
        self._client = boto3.client(
            "s3",
            endpoint_url=settings.tigris_endpoint,
            aws_access_key_id=settings.aws_access_key_id,
            aws_secret_access_key=settings.aws_secret_access_key,
            config=Config(s3={"addressing_style": "virtual"}),
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
