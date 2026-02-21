"""Whisper-based transcription service.

Transcribes audio files from presigned URLs using OpenAI Whisper (whisper-1).
Uses plain text output format (no verbose JSON or speaker diarization).
Speaker prediction is handled downstream by the summarization service.

Audio is validated for size (>0, <25MB) and duration (1s-300s) before
submission. Non-M4A audio is converted to M4A via ffmpeg as a safety net.
"""

import asyncio
import logging
import subprocess
import tempfile
from dataclasses import dataclass, field

import httpx
from openai import OpenAI

logger = logging.getLogger(__name__)

# Maximum file size for OpenAI transcription API (25 MB)
_OPENAI_MAX_BYTES = 25 * 1024 * 1024


@dataclass
class TranscriptionResult:
    """Result of a transcription operation.

    Attributes:
        utterances: Always empty list (plain text mode has no segments).
        full_text: The complete transcript as a single string.
        provider: Which provider produced this result.
        language: Detected or requested language code.
        word_count: Number of words in full_text.
    """

    utterances: list[dict] = field(default_factory=list)
    full_text: str = ""
    provider: str = ""
    language: str = "en"
    word_count: int = 0


def _get_audio_duration(audio_bytes: bytes) -> float:
    """Determine audio duration in seconds using ffprobe.

    Writes audio bytes to a temporary file and runs ffprobe to extract
    the duration. Raises ValueError if duration cannot be determined.

    Args:
        audio_bytes: Raw audio file bytes.

    Returns:
        Duration in seconds as a float.

    Raises:
        ValueError: If ffprobe fails or returns empty output.
    """
    with tempfile.NamedTemporaryFile(suffix=".m4a", delete=True) as tmp:
        tmp.write(audio_bytes)
        tmp.flush()

        try:
            proc = subprocess.run(
                [
                    "ffprobe",
                    "-v", "quiet",
                    "-show_entries", "format=duration",
                    "-of", "default=noprint_wrappers=1:nokey=1",
                    tmp.name,
                ],
                timeout=30,
                capture_output=True,
                text=True,
            )
        except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
            raise ValueError(f"Unable to determine audio duration: {exc}") from exc

        stdout = proc.stdout.strip()
        if not stdout or proc.returncode != 0:
            raise ValueError(
                f"Unable to determine audio duration: ffprobe returned "
                f"rc={proc.returncode}, stdout='{stdout}', "
                f"stderr='{proc.stderr.strip()}'"
            )

        try:
            return float(stdout)
        except ValueError as exc:
            raise ValueError(
                f"Unable to parse audio duration from ffprobe output: '{stdout}'"
            ) from exc


def _ensure_m4a(audio_bytes: bytes) -> bytes:
    """Ensure audio is in M4A container format, converting if necessary.

    Checks for the ftyp box magic bytes at offset 4-8 which indicate
    an ISO base media file (M4A/MP4). If not present, converts using
    ffmpeg with AAC codec at 128kbps.

    Args:
        audio_bytes: Raw audio file bytes.

    Returns:
        Audio bytes in M4A format (original if already M4A, converted otherwise).
    """
    # Check for M4A/MP4 ftyp magic bytes at offset 4-8
    if len(audio_bytes) >= 12 and audio_bytes[4:8] == b"ftyp":
        return audio_bytes

    logger.info(
        "Audio does not have ftyp header, converting to M4A via ffmpeg (%d bytes)",
        len(audio_bytes),
    )

    with tempfile.NamedTemporaryFile(suffix=".audio", delete=True) as infile, \
         tempfile.NamedTemporaryFile(suffix=".m4a", delete=True) as outfile:
        infile.write(audio_bytes)
        infile.flush()

        try:
            subprocess.run(
                [
                    "ffmpeg",
                    "-y",
                    "-i", infile.name,
                    "-c:a", "aac",
                    "-b:a", "128k",
                    outfile.name,
                ],
                timeout=60,
                capture_output=True,
                check=True,
            )
        except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError) as exc:
            raise ValueError(f"ffmpeg conversion to M4A failed: {exc}") from exc

        result = open(outfile.name, "rb").read()

    logger.info(
        "Converted non-M4A audio to M4A via ffmpeg (%d -> %d bytes)",
        len(audio_bytes),
        len(result),
    )

    return result


class TranscriptionService:
    """Transcribes audio using OpenAI Whisper (whisper-1).

    Usage:
        service = TranscriptionService(openai_api_key)
        result = await service.transcribe(audio_url)
    """

    def __init__(self, openai_api_key: str) -> None:
        self._openai_key = openai_api_key

    async def transcribe(self, audio_url: str) -> TranscriptionResult:
        """Transcribe audio from a presigned URL using Whisper.

        Downloads the audio, validates size and duration, ensures M4A format,
        then sends to OpenAI Whisper with plain text response format.

        Args:
            audio_url: Presigned URL pointing to the audio file.

        Returns:
            TranscriptionResult with full_text and metadata (utterances always empty).

        Raises:
            ValueError: If audio file is empty, exceeds 25 MB, is too short (<1s),
                or exceeds 5-minute limit (>300s).
        """
        # Download audio from presigned URL
        async with httpx.AsyncClient(timeout=120.0) as http_client:
            resp = await http_client.get(audio_url)
            resp.raise_for_status()
            audio_bytes = resp.content

        # Validate file size
        if len(audio_bytes) == 0:
            raise ValueError("Audio file is empty (0 bytes)")

        if len(audio_bytes) > _OPENAI_MAX_BYTES:
            raise ValueError(
                f"Audio exceeds OpenAI 25MB limit: {len(audio_bytes)} bytes"
            )

        # Validate duration
        duration = await asyncio.to_thread(_get_audio_duration, audio_bytes)
        if duration < 1.0:
            raise ValueError(f"Audio too short: {duration:.1f}s (minimum 1s)")
        if duration > 300.0:
            raise ValueError(
                f"Audio exceeds 5-minute limit: {duration:.1f}s"
            )

        # Ensure M4A format (convert via ffmpeg if needed)
        audio_bytes = await asyncio.to_thread(_ensure_m4a, audio_bytes)

        client = OpenAI(api_key=self._openai_key)

        def _call_whisper() -> object:
            return client.audio.transcriptions.create(
                model="whisper-1",
                file=("audio.m4a", audio_bytes, "audio/mp4"),
                response_format="text",
            )

        result = await asyncio.to_thread(_call_whisper)

        # Plain text response_format returns a string directly
        full_text = result.strip() if isinstance(result, str) else str(result).strip()
        word_count = len(full_text.split()) if full_text else 0

        logger.info(
            "Whisper transcription succeeded: %d words",
            word_count,
        )

        return TranscriptionResult(
            utterances=[],
            full_text=full_text,
            provider="whisper",
            language="en",
            word_count=word_count,
        )
