"""Whisper-based transcription service.

Transcribes audio files from presigned URLs using OpenAI Whisper (whisper-1).
No speaker diarization -- all segments are assigned speaker=0.
Speaker prediction is handled downstream by the summarization service.
"""

import asyncio
import logging
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
        utterances: List of dicts, each with speaker (int), text (str),
            start (float), end (float), confidence (float).
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

        Downloads the audio, then sends it to OpenAI Whisper for transcription.
        Returns segments with timestamps but no speaker diarization (all speaker=0).

        Args:
            audio_url: Presigned URL pointing to the audio file.

        Returns:
            TranscriptionResult with utterances, full text, and metadata.

        Raises:
            ValueError: If audio file exceeds 25 MB limit.
        """
        # Download audio from presigned URL
        async with httpx.AsyncClient(timeout=120.0) as http_client:
            resp = await http_client.get(audio_url)
            resp.raise_for_status()
            audio_bytes = resp.content

        if len(audio_bytes) > _OPENAI_MAX_BYTES:
            raise ValueError(
                f"Audio exceeds OpenAI 25MB limit: {len(audio_bytes)} bytes"
            )

        client = OpenAI(api_key=self._openai_key)

        def _call_whisper() -> object:
            return client.audio.transcriptions.create(
                model="whisper-1",
                file=("audio.aac", audio_bytes, "audio/aac"),
                response_format="verbose_json",
                timestamp_granularities=["segment"],
            )

        result = await asyncio.to_thread(_call_whisper)

        # Parse segments into utterances format.
        # Whisper has no diarization, so all segments get speaker=0.
        utterances: list[dict] = []
        segments = getattr(result, "segments", None) or []
        for seg in segments:
            utterances.append(
                {
                    "speaker": 0,
                    "text": seg.get("text", "").strip() if isinstance(seg, dict) else getattr(seg, "text", "").strip(),
                    "start": seg.get("start", 0.0) if isinstance(seg, dict) else getattr(seg, "start", 0.0),
                    "end": seg.get("end", 0.0) if isinstance(seg, dict) else getattr(seg, "end", 0.0),
                    "confidence": seg.get("avg_logprob", 0.0) if isinstance(seg, dict) else getattr(seg, "avg_logprob", 0.0),
                }
            )

        full_text = getattr(result, "text", "") or ""

        logger.info(
            "Whisper transcription succeeded: %d words, %d segments",
            len(full_text.split()) if full_text else 0,
            len(utterances),
        )

        return TranscriptionResult(
            utterances=utterances,
            full_text=full_text,
            provider="whisper",
            language=getattr(result, "language", "en") or "en",
            word_count=len(full_text.split()) if full_text else 0,
        )
