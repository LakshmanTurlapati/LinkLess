"""Unified AI provider abstraction for transcription and summarization.

Supports: OpenAI (Whisper + GPT), Anthropic (Claude), Google (Gemini), xAI (Grok).
"""

from abc import ABC, abstractmethod
from typing import Optional

from app.config import settings


class TranscriptionResult:
    """Result from audio transcription."""

    def __init__(
        self,
        text: str,
        segments: list[dict],
        language: str = "en",
        confidence: float = 1.0,
    ):
        self.text = text
        self.segments = segments
        self.language = language
        self.confidence = confidence


class SummarizationResult:
    """Result from conversation summarization."""

    def __init__(self, summary: str, topics: list[str], key_points: list[str]):
        self.summary = summary
        self.topics = topics
        self.key_points = key_points


class AIProvider(ABC):
    """Abstract base for AI providers."""

    @abstractmethod
    async def transcribe_audio(self, audio_path: str) -> TranscriptionResult:
        """Transcribe an audio file to text with speaker segments."""
        ...

    @abstractmethod
    async def summarize_conversation(
        self, transcript: str, participants: list[str]
    ) -> SummarizationResult:
        """Summarize a conversation transcript, extract topics and key points."""
        ...


class OpenAIProvider(AIProvider):
    """OpenAI — Whisper for transcription, GPT-4 for summarization."""

    def __init__(self):
        from openai import AsyncOpenAI

        self.client = AsyncOpenAI(api_key=settings.openai_api_key)

    async def transcribe_audio(self, audio_path: str) -> TranscriptionResult:
        with open(audio_path, "rb") as audio_file:
            response = await self.client.audio.transcriptions.create(
                model="whisper-1",
                file=audio_file,
                response_format="verbose_json",
                timestamp_granularities=["segment"],
            )

        segments = []
        if hasattr(response, "segments") and response.segments:
            for seg in response.segments:
                segments.append(
                    {
                        "text": seg.text.strip(),
                        "start": seg.start,
                        "end": seg.end,
                        "confidence": getattr(seg, "avg_logprob", 0.9),
                    }
                )

        return TranscriptionResult(
            text=response.text,
            segments=segments,
            language=getattr(response, "language", "en"),
        )

    async def summarize_conversation(
        self, transcript: str, participants: list[str]
    ) -> SummarizationResult:
        prompt = _build_summarization_prompt(transcript, participants)

        response = await self.client.chat.completions.create(
            model="gpt-4o",
            messages=[
                {
                    "role": "system",
                    "content": "You are an AI assistant that summarizes conversations between students. Extract key topics, main points, and create a concise summary.",
                },
                {"role": "user", "content": prompt},
            ],
            temperature=0.3,
        )

        return _parse_summarization_response(response.choices[0].message.content)


class AnthropicProvider(AIProvider):
    """Anthropic — Claude for summarization (uses OpenAI Whisper for transcription)."""

    def __init__(self):
        import anthropic
        self.client = anthropic.AsyncAnthropic(api_key=settings.anthropic_api_key)
        # Anthropic doesn't have a transcription API, fall back to OpenAI for that
        self._transcription_fallback: Optional[OpenAIProvider] = None
        if settings.openai_api_key:
            self._transcription_fallback = OpenAIProvider()

    async def transcribe_audio(self, audio_path: str) -> TranscriptionResult:
        if self._transcription_fallback:
            return await self._transcription_fallback.transcribe_audio(audio_path)
        raise NotImplementedError(
            "Anthropic does not support audio transcription. "
            "Set OPENAI_API_KEY for transcription fallback."
        )

    async def summarize_conversation(
        self, transcript: str, participants: list[str]
    ) -> SummarizationResult:
        prompt = _build_summarization_prompt(transcript, participants)

        response = await self.client.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=1024,
            messages=[{"role": "user", "content": prompt}],
            system="You are an AI assistant that summarizes conversations between students. Extract key topics, main points, and create a concise summary.",
        )

        text = response.content[0].text
        return _parse_summarization_response(text)


class GoogleProvider(AIProvider):
    """Google — Gemini for both transcription and summarization."""

    def __init__(self):
        import google.generativeai as genai

        genai.configure(api_key=settings.google_api_key)
        self.model = genai.GenerativeModel("gemini-1.5-pro")

    async def transcribe_audio(self, audio_path: str) -> TranscriptionResult:
        # Upload audio file to Gemini
        import google.generativeai as genai

        audio_file = genai.upload_file(audio_path)

        response = await self.model.generate_content_async(
            [
                audio_file,
                "Transcribe this audio. For each segment of speech, provide the text "
                "along with approximate timestamps. Format each segment as: "
                "[START-END] Speaker: text",
            ]
        )

        text = response.text
        segments = _parse_gemini_transcript(text)

        return TranscriptionResult(text=text, segments=segments)

    async def summarize_conversation(
        self, transcript: str, participants: list[str]
    ) -> SummarizationResult:
        prompt = _build_summarization_prompt(transcript, participants)

        response = await self.model.generate_content_async(prompt)
        return _parse_summarization_response(response.text)


class XAIProvider(AIProvider):
    """xAI — Grok for summarization (uses OpenAI Whisper for transcription)."""

    def __init__(self):
        from openai import AsyncOpenAI

        self.client = AsyncOpenAI(
            api_key=settings.xai_api_key,
            base_url="https://api.x.ai/v1",
        )
        # xAI uses OpenAI-compatible API but may not have transcription
        self._transcription_fallback: Optional[OpenAIProvider] = None
        if settings.openai_api_key:
            self._transcription_fallback = OpenAIProvider()

    async def transcribe_audio(self, audio_path: str) -> TranscriptionResult:
        if self._transcription_fallback:
            return await self._transcription_fallback.transcribe_audio(audio_path)
        raise NotImplementedError(
            "xAI does not support audio transcription. "
            "Set OPENAI_API_KEY for transcription fallback."
        )

    async def summarize_conversation(
        self, transcript: str, participants: list[str]
    ) -> SummarizationResult:
        prompt = _build_summarization_prompt(transcript, participants)

        response = await self.client.chat.completions.create(
            model="grok-2",
            messages=[
                {
                    "role": "system",
                    "content": "You are an AI assistant that summarizes conversations between students. Extract key topics, main points, and create a concise summary.",
                },
                {"role": "user", "content": prompt},
            ],
            temperature=0.3,
        )

        return _parse_summarization_response(response.choices[0].message.content)


# ─── Helpers ─────────────────────────────────────────────────────────


def _build_summarization_prompt(transcript: str, participants: list[str]) -> str:
    return f"""Summarize the following conversation between {', '.join(participants)}.

Provide your response in this exact format:

SUMMARY:
<A concise 2-3 sentence summary of the conversation>

TOPICS:
- <topic 1>
- <topic 2>
- <topic 3>

KEY POINTS:
- <key point 1>
- <key point 2>
- <key point 3>

--- TRANSCRIPT ---
{transcript}
"""


def _parse_summarization_response(text: str) -> SummarizationResult:
    """Parse the structured summarization response."""
    summary = ""
    topics = []
    key_points = []

    current_section = None
    for line in text.strip().split("\n"):
        line = line.strip()
        if line.startswith("SUMMARY:"):
            current_section = "summary"
            continue
        elif line.startswith("TOPICS:"):
            current_section = "topics"
            continue
        elif line.startswith("KEY POINTS:"):
            current_section = "key_points"
            continue

        if current_section == "summary" and line:
            summary += line + " "
        elif current_section == "topics" and line.startswith("- "):
            topics.append(line[2:].strip())
        elif current_section == "key_points" and line.startswith("- "):
            key_points.append(line[2:].strip())

    return SummarizationResult(
        summary=summary.strip(),
        topics=topics or ["General conversation"],
        key_points=key_points,
    )


def _parse_gemini_transcript(text: str) -> list[dict]:
    """Parse Gemini's transcript format into structured segments."""
    segments = []
    for line in text.strip().split("\n"):
        line = line.strip()
        if not line:
            continue
        # Try to parse [START-END] Speaker: text format
        segments.append({"text": line, "start": 0.0, "end": 0.0, "confidence": 0.85})
    return segments


def get_ai_provider() -> AIProvider:
    """Factory to get the configured AI provider."""
    provider = settings.ai_provider.lower()

    if provider == "openai":
        return OpenAIProvider()
    elif provider == "anthropic":
        return AnthropicProvider()
    elif provider == "google":
        return GoogleProvider()
    elif provider == "xai":
        return XAIProvider()
    else:
        raise ValueError(
            f"Unknown AI provider: {provider}. "
            "Supported: openai, anthropic, google, xai"
        )
