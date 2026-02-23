"""Debug-only API routes for AI chat testing.

Provides a streaming SSE chat endpoint that proxies messages to xAI Grok
using the same system prompt as production summarization. All endpoints
are gated behind DEBUG_MODE and return 404 when it is off.
"""

import asyncio
import json
import logging
import time

from fastapi import APIRouter, Depends, Request
from openai import AsyncOpenAI
from sse_starlette.sse import EventSourceResponse

from app.api.v1.routes.conversations import require_debug_mode
from app.core.config import settings
from app.core.dependencies import get_current_user
from app.models.user import User
from app.schemas.debug import ChatRequest
from app.services.summarization_service import SUMMARIZATION_SYSTEM_PROMPT

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/debug", tags=["debug"])

_MODEL_ID = "grok-4-1-fast-non-reasoning"
_STREAM_TIMEOUT_SECONDS = 15.0


def _map_error(exc: Exception) -> str:
    """Map an AI provider exception to a human-readable error message."""
    err_str = str(exc).lower()

    if "401" in err_str or "invalid" in err_str or "api key" in err_str:
        return "API key invalid"
    if "404" in err_str or "model" in err_str:
        return "Model unreachable"
    if "429" in err_str or "rate" in err_str:
        return "Rate limit exceeded"
    if "timeout" in err_str:
        return "Request timed out"
    if "connection" in err_str:
        return "Cannot connect to AI provider"

    return f"AI error: {str(exc)[:100]}"


@router.post(
    "/chat",
    dependencies=[Depends(require_debug_mode)],
)
async def debug_chat(
    body: ChatRequest,
    request: Request,
    _user: User = Depends(get_current_user),
) -> EventSourceResponse:
    """Stream AI chat response as Server-Sent Events.

    Sends the user message to xAI Grok using the production summarization
    system prompt and streams token-by-token responses back via SSE.

    Events:
        token: {"content": "..."} -- a chunk of generated text
        done:  {"token_count": N, "latency_ms": N, "model_id": "..."} -- stream complete
        error: {"error": "..."} -- human-readable error description

    Returns 404 when DEBUG_MODE is off (via require_debug_mode dependency).
    """
    client = AsyncOpenAI(
        api_key=settings.xai_api_key,
        base_url="https://api.x.ai/v1",
    )
    start_time = time.monotonic()

    async def event_generator():
        token_count = 0

        try:
            # The 15s timeout applies only to the initial API call,
            # not the entire stream duration.
            stream = await asyncio.wait_for(
                client.chat.completions.create(
                    model=_MODEL_ID,
                    stream=True,
                    temperature=0.3,
                    max_tokens=500,
                    messages=[
                        {
                            "role": "system",
                            "content": SUMMARIZATION_SYSTEM_PROMPT,
                        },
                        {"role": "user", "content": body.message},
                    ],
                ),
                timeout=_STREAM_TIMEOUT_SECONDS,
            )

            async for chunk in stream:
                if await request.is_disconnected():
                    break

                delta = chunk.choices[0].delta if chunk.choices else None
                if delta and delta.content:
                    token_count += 1
                    yield {
                        "event": "token",
                        "data": json.dumps({"content": delta.content}),
                    }

        except asyncio.TimeoutError:
            yield {
                "event": "error",
                "data": json.dumps(
                    {"error": "Request timed out (15s)"}
                ),
            }
            return

        except Exception as exc:
            logger.exception("Debug chat error: %s", exc)
            yield {
                "event": "error",
                "data": json.dumps({"error": _map_error(exc)}),
            }
            return

        # Stream completed successfully
        latency_ms = int((time.monotonic() - start_time) * 1000)
        yield {
            "event": "done",
            "data": json.dumps(
                {
                    "token_count": token_count,
                    "latency_ms": latency_ms,
                    "model_id": _MODEL_ID,
                }
            ),
        }

    return EventSourceResponse(event_generator())
