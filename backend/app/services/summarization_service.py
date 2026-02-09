"""LLM-based conversation summarization service.

Generates a concise summary, key topics, and predicted speaker count from a
conversation transcript using xAI Grok 4-1-fast via the OpenAI-compatible API.
"""

import json
import logging
from dataclasses import dataclass, field

from openai import AsyncOpenAI

logger = logging.getLogger(__name__)

_SYSTEM_PROMPT = (
    "You are a conversation analyzer. Given a raw transcript of a conversation "
    "between two or more people, do the following:\n"
    "1. Predict which parts were spoken by different speakers based on "
    "conversational context, topic shifts, and dialogue patterns.\n"
    "2. Produce a JSON object with exactly three fields:\n"
    '- "summary": A 2-3 sentence summary of the conversation.\n'
    '- "key_topics": A list of 3-5 short strings representing the main topics.\n'
    '- "speaker_count": The predicted number of distinct speakers (integer).\n'
    "Respond ONLY with valid JSON. No extra text."
)

# Minimum word count for a meaningful transcript
_MIN_WORD_COUNT = 10


@dataclass
class SummaryResult:
    """Result of a summarization operation.

    Attributes:
        summary: A 2-3 sentence summary of the conversation.
        key_topics: List of 3-5 key topic strings.
        speaker_count: Predicted number of distinct speakers.
        provider: Which LLM provider produced this result.
    """

    summary: str = ""
    key_topics: list[str] = field(default_factory=list)
    speaker_count: int = 0
    provider: str = ""


class SummarizationService:
    """Generates conversation summaries using xAI Grok 4-1-fast.

    Usage:
        service = SummarizationService(xai_api_key)
        result = await service.summarize(transcript_text)
    """

    def __init__(self, xai_api_key: str) -> None:
        self._xai_key = xai_api_key

    async def summarize(self, transcript_text: str) -> SummaryResult:
        """Summarize a conversation transcript.

        If the transcript is empty or very short (fewer than 10 words),
        returns a default result without calling the LLM.

        Args:
            transcript_text: Plain text transcript of the conversation.

        Returns:
            SummaryResult with summary text, key topics, and speaker count.
        """
        # Handle empty or very short transcripts
        if not transcript_text or len(transcript_text.split()) < _MIN_WORD_COUNT:
            logger.info(
                "Transcript too short for summarization (%d words), using default",
                len(transcript_text.split()) if transcript_text else 0,
            )
            return SummaryResult(
                summary="Brief or empty conversation",
                key_topics=[],
                speaker_count=0,
                provider="grok",
            )

        client = AsyncOpenAI(
            api_key=self._xai_key,
            base_url="https://api.x.ai/v1",
        )

        response = await client.chat.completions.create(
            model="grok-4-1-fast",
            messages=[
                {"role": "system", "content": _SYSTEM_PROMPT},
                {"role": "user", "content": f"Transcript:\n{transcript_text}"},
            ],
            response_format={"type": "json_object"},
            temperature=0.3,
            max_tokens=500,
        )

        raw_content = response.choices[0].message.content or "{}"

        try:
            parsed = json.loads(raw_content)
        except json.JSONDecodeError:
            logger.error(
                "Failed to parse LLM response as JSON: %s", raw_content[:200]
            )
            return SummaryResult(
                summary="Summary generation failed",
                key_topics=[],
                speaker_count=0,
                provider="grok",
            )

        summary_text = parsed.get("summary", "")
        key_topics = parsed.get("key_topics", [])
        speaker_count = parsed.get("speaker_count", 0)

        # Validate types
        if not isinstance(summary_text, str):
            summary_text = str(summary_text)
        if not isinstance(key_topics, list):
            key_topics = []
        key_topics = [str(t) for t in key_topics if t]
        if not isinstance(speaker_count, int):
            try:
                speaker_count = int(speaker_count)
            except (ValueError, TypeError):
                speaker_count = 0

        logger.info(
            "Summarization complete: %d chars summary, %d topics, %d speakers",
            len(summary_text),
            len(key_topics),
            speaker_count,
        )

        return SummaryResult(
            summary=summary_text,
            key_topics=key_topics,
            speaker_count=speaker_count,
            provider="grok",
        )
