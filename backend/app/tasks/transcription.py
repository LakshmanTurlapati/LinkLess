"""ARQ task for transcribing conversation audio.

Processes audio files through TranscriptionService (OpenAI Whisper),
stores results in the transcripts table, and chains to summarization.
"""

import logging

from arq import Retry
from sqlalchemy import select

from app.core.config import settings
from app.models.conversation import Conversation, Transcript
from app.services.storage_service import StorageService
from app.services.transcription_service import TranscriptionService

logger = logging.getLogger(__name__)


async def transcribe_conversation(ctx: dict, conversation_id: str) -> None:
    """Transcribe a conversation's audio and chain to summarization.

    Idempotent: skips if transcript already exists for this conversation.
    Retries once with 30s delay on failure.
    After 2 failed attempts, marks conversation as "failed".

    Args:
        ctx: ARQ worker context containing db_session_factory and redis.
        conversation_id: UUID string of the conversation to transcribe.
    """
    job_try = ctx.get("job_try", 1)
    logger.info(
        "transcribe_conversation started: conversation_id=%s, attempt=%d",
        conversation_id,
        job_try,
    )

    async with ctx["db_session_factory"]() as session:
        # Idempotency check: skip if transcript already exists
        existing = await session.execute(
            select(Transcript).where(
                Transcript.conversation_id == conversation_id
            )
        )
        if existing.scalar_one_or_none() is not None:
            logger.info(
                "Transcript already exists for conversation %s, skipping",
                conversation_id,
            )
            return

        # Fetch conversation
        result = await session.execute(
            select(Conversation).where(Conversation.id == conversation_id)
        )
        conversation = result.scalar_one_or_none()
        if conversation is None:
            logger.error(
                "Conversation %s not found, aborting transcription",
                conversation_id,
            )
            return

        # Check valid status for transcription
        if conversation.status not in ("uploaded", "transcribing"):
            logger.warning(
                "Conversation %s has status '%s', expected 'uploaded' or 'transcribing'. Skipping.",
                conversation_id,
                conversation.status,
            )
            return

        try:
            # Update status to transcribing
            conversation.status = "transcribing"
            await session.commit()

            # Generate presigned download URL for the audio file
            storage = StorageService()
            download_url = storage.generate_download_url(
                key=conversation.audio_storage_key,
                expires_in=3600,
            )

            # Transcribe with OpenAI Whisper
            transcription_service = TranscriptionService(
                openai_api_key=settings.openai_api_key,
            )
            transcription_result = await transcription_service.transcribe(
                download_url
            )

            # Store transcript in database
            transcript = Transcript(
                conversation_id=conversation.id,
                content=transcription_result.full_text,
                provider=transcription_result.provider,
                language=transcription_result.language,
                word_count=transcription_result.word_count,
            )
            session.add(transcript)

            # Update conversation status
            conversation.status = "transcribed"
            await session.commit()

            logger.info(
                "Transcription complete for conversation %s: provider=%s, words=%d",
                conversation_id,
                transcription_result.provider,
                transcription_result.word_count,
            )

            # Chain to summarization task
            redis = ctx["redis"]
            await redis.enqueue_job(
                "summarize_conversation", str(conversation_id)
            )
            logger.info(
                "Enqueued summarization for conversation %s",
                conversation_id,
            )

        except Exception as exc:
            await session.rollback()

            if job_try >= 2:
                # Max retries exhausted, mark as failed
                async with ctx["db_session_factory"]() as fail_session:
                    fail_result = await fail_session.execute(
                        select(Conversation).where(
                            Conversation.id == conversation_id
                        )
                    )
                    fail_conv = fail_result.scalar_one_or_none()
                    if fail_conv is not None:
                        fail_conv.status = "failed"
                        fail_conv.error_detail = str(exc)[:500]
                        await fail_session.commit()

                logger.error(
                    "Transcription failed after %d attempts for conversation %s: %s",
                    job_try,
                    conversation_id,
                    exc,
                )
                raise

            # Retry with fixed 30s delay
            defer_seconds = 30
            logger.warning(
                "Transcription attempt %d failed for conversation %s, retrying in %ds: %s",
                job_try,
                conversation_id,
                defer_seconds,
                exc,
            )
            raise Retry(defer=defer_seconds)
