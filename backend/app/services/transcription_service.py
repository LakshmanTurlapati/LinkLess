"""Multi-provider transcription service with Deepgram primary and OpenAI fallback.

Transcribes audio files from presigned URLs with speaker diarization.
Deepgram Nova-3 is the primary provider. If Deepgram fails for any reason,
falls back to OpenAI gpt-4o-transcribe.
"""

import asyncio
import logging
from dataclasses import dataclass, field

import httpx
from deepgram import DeepgramClient
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
        provider: Which provider produced this result ("deepgram" or "openai").
        language: Detected or requested language code.
        word_count: Number of words in full_text.
    """

    utterances: list[dict] = field(default_factory=list)
    full_text: str = ""
    provider: str = ""
    language: str = "en"
    word_count: int = 0


class TranscriptionService:
    """Transcribes audio using Deepgram Nova-3 with OpenAI fallback.

    Usage:
        service = TranscriptionService(deepgram_key, openai_key)
        result = await service.transcribe(audio_url)
    """

    def __init__(self, deepgram_api_key: str, openai_api_key: str) -> None:
        self._deepgram_key = deepgram_api_key
        self._openai_key = openai_api_key

    async def transcribe(self, audio_url: str) -> TranscriptionResult:
        """Transcribe audio from a presigned URL.

        Tries Deepgram Nova-3 first. On any exception, falls back to OpenAI.

        Args:
            audio_url: Presigned URL pointing to the audio file.

        Returns:
            TranscriptionResult with utterances, full text, and metadata.

        Raises:
            Exception: If both providers fail.
        """
        try:
            result = await self._transcribe_deepgram(audio_url)
            logger.info(
                "Deepgram transcription succeeded: %d words, %d utterances",
                result.word_count,
                len(result.utterances),
            )
            return result
        except Exception as exc:
            logger.warning(
                "Deepgram transcription failed, falling back to OpenAI: %s",
                exc,
            )
            result = await self._transcribe_openai(audio_url)
            logger.info(
                "OpenAI transcription succeeded: %d words, %d utterances",
                result.word_count,
                len(result.utterances),
            )
            return result

    async def _transcribe_deepgram(self, audio_url: str) -> TranscriptionResult:
        """Transcribe using Deepgram Nova-3 with speaker diarization.

        The Deepgram SDK v5 uses synchronous HTTP internally, so the call
        is wrapped in asyncio.to_thread to avoid blocking the event loop.

        Args:
            audio_url: Presigned URL pointing to the audio file.

        Returns:
            TranscriptionResult from Deepgram.
        """
        client = DeepgramClient(api_key=self._deepgram_key)

        def _call_deepgram() -> object:
            return client.listen.v1.media.transcribe_url(
                url=audio_url,
                model="nova-3",
                smart_format=True,
                diarize=True,
                utterances=True,
                language="en",
            )

        response = await asyncio.to_thread(_call_deepgram)

        # Extract utterances from response
        utterances: list[dict] = []
        if response.results.utterances:
            for utt in response.results.utterances:
                utterances.append(
                    {
                        "speaker": utt.speaker,
                        "text": utt.transcript,
                        "start": utt.start,
                        "end": utt.end,
                        "confidence": utt.confidence,
                    }
                )

        # Extract full text from first channel alternative
        full_text = ""
        if (
            response.results.channels
            and response.results.channels[0].alternatives
        ):
            full_text = (
                response.results.channels[0].alternatives[0].transcript
            )

        return TranscriptionResult(
            utterances=utterances,
            full_text=full_text,
            provider="deepgram",
            language="en",
            word_count=len(full_text.split()) if full_text else 0,
        )

    async def _transcribe_openai(self, audio_url: str) -> TranscriptionResult:
        """Transcribe using OpenAI gpt-4o-transcribe as fallback.

        Downloads the audio file first (OpenAI requires file upload, not URL).
        If the file exceeds 25 MB, raises ValueError.

        Args:
            audio_url: Presigned URL pointing to the audio file.

        Returns:
            TranscriptionResult from OpenAI.

        Raises:
            ValueError: If audio file exceeds 25 MB OpenAI limit.
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

        def _call_openai() -> object:
            return client.audio.transcriptions.create(
                model="gpt-4o-transcribe",
                file=("audio.aac", audio_bytes, "audio/aac"),
                response_format="verbose_json",
                timestamp_granularities=["segment"],
            )

        result = await asyncio.to_thread(_call_openai)

        # Parse segments into utterances format
        # OpenAI gpt-4o-transcribe returns segments but no speaker diarization,
        # so all utterances are assigned speaker=0.
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

        return TranscriptionResult(
            utterances=utterances,
            full_text=full_text,
            provider="openai",
            language=getattr(result, "language", "en") or "en",
            word_count=len(full_text.split()) if full_text else 0,
        )
