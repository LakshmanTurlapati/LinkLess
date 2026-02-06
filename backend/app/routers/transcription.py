"""Transcription and AI summarization endpoints."""

import os
import uuid

from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.config import settings
from app.database import get_db
from app.models import User, Encounter, TranscriptSegment, EncounterStatus
from app.auth_utils import get_current_user
from app.ai import get_ai_provider

router = APIRouter()


@router.post("/{encounter_id}/transcribe")
async def transcribe_audio_chunk(
    encounter_id: str,
    audio: UploadFile = File(...),
    chunk_index: int = Form(0),
    is_final: bool = Form(False),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Transcribe an audio chunk from a conversation.

    The mobile app records audio in chunks and uploads them for transcription.
    Each chunk is transcribed using the configured AI provider and the resulting
    segments are stored in the database.
    """
    # Verify encounter exists and user is a participant
    result = await db.execute(
        select(Encounter)
        .where(Encounter.id == encounter_id)
        .options(selectinload(Encounter.peer), selectinload(Encounter.user))
    )
    encounter = result.scalar_one_or_none()

    if not encounter:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Encounter not found",
        )

    if encounter.user_id != current_user.id and encounter.peer_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to add transcription to this encounter",
        )

    if encounter.status != EncounterStatus.ACTIVE:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Encounter is not active",
        )

    # Save the uploaded audio file temporarily
    os.makedirs(settings.upload_dir, exist_ok=True)
    temp_path = os.path.join(
        settings.upload_dir,
        f"audio_{encounter_id}_{chunk_index}_{uuid.uuid4().hex[:8]}.m4a",
    )

    content = await audio.read()
    with open(temp_path, "wb") as f:
        f.write(content)

    try:
        # Transcribe using the configured AI provider
        ai = get_ai_provider()
        transcription = await ai.transcribe_audio(temp_path)

        # Create transcript segments
        segments = []
        for seg in transcription.segments:
            segment = TranscriptSegment(
                encounter_id=encounter_id,
                speaker_id=current_user.id,
                speaker_name=current_user.display_name,
                text=seg.get("text", ""),
                confidence=seg.get("confidence", transcription.confidence),
                chunk_index=str(chunk_index),
            )
            db.add(segment)
            segments.append(segment)

        # If there were no segments but we have full text, create one segment
        if not segments and transcription.text.strip():
            segment = TranscriptSegment(
                encounter_id=encounter_id,
                speaker_id=current_user.id,
                speaker_name=current_user.display_name,
                text=transcription.text.strip(),
                confidence=transcription.confidence,
                chunk_index=str(chunk_index),
            )
            db.add(segment)
            segments.append(segment)

        await db.flush()

        return {
            "segments": [seg.to_dict() for seg in segments],
            "chunk_index": chunk_index,
            "is_final": is_final,
            "full_text": transcription.text,
        }

    finally:
        # Clean up temp file
        try:
            os.remove(temp_path)
        except OSError:
            pass


@router.post("/{encounter_id}/summarize")
async def summarize_encounter(
    encounter_id: str,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """
    Generate an AI summary of the encounter's full transcript.

    Extracts topics, key points, and creates a concise summary using the
    configured AI provider.
    """
    result = await db.execute(
        select(Encounter)
        .where(Encounter.id == encounter_id)
        .options(
            selectinload(Encounter.peer),
            selectinload(Encounter.user),
            selectinload(Encounter.transcript_segments),
        )
    )
    encounter = result.scalar_one_or_none()

    if not encounter:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Encounter not found",
        )

    if encounter.user_id != current_user.id and encounter.peer_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Not authorized to summarize this encounter",
        )

    if not encounter.transcript_segments:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="No transcript available to summarize",
        )

    # Build the full transcript text
    transcript_lines = []
    for seg in sorted(encounter.transcript_segments, key=lambda s: s.timestamp):
        transcript_lines.append(f"{seg.speaker_name}: {seg.text}")
    transcript_text = "\n".join(transcript_lines)

    participants = [encounter.user.display_name, encounter.peer.display_name]

    # Summarize using AI
    ai = get_ai_provider()
    summary_result = await ai.summarize_conversation(transcript_text, participants)

    # Save summary to encounter
    encounter.summary = summary_result.summary
    encounter.topics = summary_result.topics
    await db.flush()

    return {
        "summary": summary_result.summary,
        "topics": summary_result.topics,
        "key_points": summary_result.key_points,
    }
