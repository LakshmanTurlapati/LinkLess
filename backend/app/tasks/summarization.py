"""ARQ task for summarizing conversation transcripts.

Generates an AI summary and key topics from a conversation transcript
and stores the result in the summaries table.
"""

import json
import logging

from arq import Retry
from sqlalchemy import select

from app.core.config import settings
from app.models.conversation import Conversation, Summary, Transcript
from app.services.summarization_service import SummarizationService

logger = logging.getLogger(__name__)


async def summarize_conversation(ctx: dict, conversation_id: str) -> None:
    """Summarize a conversation transcript and update status to completed.

    Idempotent: skips if summary already exists for this conversation.
    Retries once with 30s delay on failure. After 2 failed attempts, marks
    conversation as 'summarization_failed' (partial success -- transcript
    preserved).

    Args:
        ctx: ARQ worker context containing db_session_factory.
        conversation_id: UUID string of the conversation to summarize.
    """
    job_try = ctx.get("job_try", 1)
    logger.info(
        "summarize_conversation started: conversation_id=%s, attempt=%d",
        conversation_id,
        job_try,
    )

    async with ctx["db_session_factory"]() as session:
        # Idempotency check: skip if summary already exists
        existing = await session.execute(
            select(Summary).where(
                Summary.conversation_id == conversation_id
            )
        )
        if existing.scalar_one_or_none() is not None:
            logger.info(
                "Summary already exists for conversation %s, skipping",
                conversation_id,
            )
            return

        # Fetch transcript for this conversation
        result = await session.execute(
            select(Transcript).where(
                Transcript.conversation_id == conversation_id
            )
        )
        transcript = result.scalar_one_or_none()
        if transcript is None:
            logger.error(
                "Transcript not found for conversation %s, cannot summarize",
                conversation_id,
            )
            return

        try:
            # Read transcript content as plain text
            transcript_text = transcript.content

            # Generate summary via Grok
            summarization_service = SummarizationService(
                xai_api_key=settings.xai_api_key
            )
            summary_result = await summarization_service.summarize(
                transcript_text
            )

            # Store summary in database
            summary = Summary(
                conversation_id=conversation_id,
                content=summary_result.summary,
                key_topics=json.dumps(summary_result.key_topics),
                provider=summary_result.provider,
            )
            session.add(summary)

            # Update conversation status to completed
            conv_result = await session.execute(
                select(Conversation).where(
                    Conversation.id == conversation_id
                )
            )
            conversation = conv_result.scalar_one_or_none()
            if conversation is not None:
                conversation.status = "completed"

            await session.commit()

            logger.info(
                "Summarization complete for conversation %s: %d topics",
                conversation_id,
                len(summary_result.key_topics),
            )

        except Exception as exc:
            await session.rollback()

            if job_try >= 2:
                # Max retries exhausted, mark as summarization_failed
                # (partial success -- transcript is preserved)
                async with ctx["db_session_factory"]() as fail_session:
                    fail_result = await fail_session.execute(
                        select(Conversation).where(
                            Conversation.id == conversation_id
                        )
                    )
                    fail_conv = fail_result.scalar_one_or_none()
                    if fail_conv is not None:
                        fail_conv.status = "summarization_failed"
                        fail_conv.error_detail = f"Summarization: {str(exc)[:480]}"
                        await fail_session.commit()

                logger.error(
                    "Summarization failed after %d attempts for conversation %s: %s",
                    job_try,
                    conversation_id,
                    exc,
                )
                raise

            # Retry once with 30s delay
            defer_seconds = 30
            logger.warning(
                "Summarization attempt %d failed for conversation %s, retrying in %ds: %s",
                job_try,
                conversation_id,
                defer_seconds,
                exc,
            )
            raise Retry(defer=defer_seconds)
