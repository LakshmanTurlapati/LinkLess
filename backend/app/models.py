"""SQLAlchemy database models for LinkLess."""

import uuid
from datetime import datetime

from sqlalchemy import (
    Column,
    String,
    Text,
    DateTime,
    Float,
    Boolean,
    ForeignKey,
    JSON,
    Enum as SAEnum,
)
from sqlalchemy.orm import relationship
import enum

from app.database import Base


def generate_uuid() -> str:
    return str(uuid.uuid4())


class PrivacyMode(str, enum.Enum):
    PUBLIC = "public"
    ANONYMOUS = "anonymous"


class EncounterStatus(str, enum.Enum):
    ACTIVE = "active"
    COMPLETED = "completed"
    CANCELLED = "cancelled"


class User(Base):
    __tablename__ = "users"

    id = Column(String, primary_key=True, default=generate_uuid)
    email = Column(String, unique=True, nullable=False, index=True)
    password_hash = Column(String, nullable=False)
    display_name = Column(String, nullable=False)
    photo_url = Column(String, nullable=True)
    bio = Column(Text, nullable=True)
    privacy_mode = Column(
        SAEnum(PrivacyMode), default=PrivacyMode.PUBLIC, nullable=False
    )
    social_links = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    updated_at = Column(
        DateTime, default=datetime.utcnow, onupdate=datetime.utcnow, nullable=False
    )

    # Relationships
    encounters_as_user = relationship(
        "Encounter", foreign_keys="Encounter.user_id", back_populates="user"
    )
    encounters_as_peer = relationship(
        "Encounter", foreign_keys="Encounter.peer_id", back_populates="peer"
    )

    def to_dict(self, include_email: bool = False) -> dict:
        """Convert to dictionary, respecting privacy settings."""
        data = {
            "id": self.id,
            "display_name": self.display_name
            if self.privacy_mode == PrivacyMode.PUBLIC
            else "Anonymous User",
            "photo_url": self.photo_url
            if self.privacy_mode == PrivacyMode.PUBLIC
            else None,
            "bio": self.bio if self.privacy_mode == PrivacyMode.PUBLIC else None,
            "privacy_mode": self.privacy_mode.value,
            "social_links": self.social_links
            if self.privacy_mode == PrivacyMode.PUBLIC
            else None,
            "created_at": self.created_at.isoformat(),
            "updated_at": self.updated_at.isoformat(),
        }
        if include_email:
            data["email"] = self.email
        return data


class Encounter(Base):
    __tablename__ = "encounters"

    id = Column(String, primary_key=True, default=generate_uuid)
    user_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    peer_id = Column(String, ForeignKey("users.id"), nullable=False, index=True)
    started_at = Column(DateTime, default=datetime.utcnow, nullable=False)
    ended_at = Column(DateTime, nullable=True)
    status = Column(
        SAEnum(EncounterStatus), default=EncounterStatus.ACTIVE, nullable=False
    )
    proximity_distance = Column(Float, nullable=True)
    summary = Column(Text, nullable=True)
    topics = Column(JSON, nullable=True)

    # Relationships
    user = relationship("User", foreign_keys=[user_id], back_populates="encounters_as_user")
    peer = relationship("User", foreign_keys=[peer_id], back_populates="encounters_as_peer")
    transcript_segments = relationship(
        "TranscriptSegment", back_populates="encounter", cascade="all, delete-orphan"
    )

    def to_dict(self, include_peer: bool = False) -> dict:
        data = {
            "id": self.id,
            "user_id": self.user_id,
            "peer_id": self.peer_id,
            "started_at": self.started_at.isoformat(),
            "ended_at": self.ended_at.isoformat() if self.ended_at else None,
            "status": self.status.value,
            "proximity_distance": self.proximity_distance,
            "summary": self.summary,
            "topics": self.topics or [],
            "transcript": [seg.to_dict() for seg in self.transcript_segments],
        }
        if include_peer and self.peer:
            data["peer_user"] = self.peer.to_dict()
        return data


class TranscriptSegment(Base):
    __tablename__ = "transcript_segments"

    id = Column(String, primary_key=True, default=generate_uuid)
    encounter_id = Column(
        String, ForeignKey("encounters.id"), nullable=False, index=True
    )
    speaker_id = Column(String, ForeignKey("users.id"), nullable=False)
    speaker_name = Column(String, nullable=False)
    text = Column(Text, nullable=False)
    timestamp = Column(DateTime, default=datetime.utcnow, nullable=False)
    confidence = Column(Float, default=1.0)
    chunk_index = Column(String, nullable=True)

    # Relationships
    encounter = relationship("Encounter", back_populates="transcript_segments")

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "speaker_id": self.speaker_id,
            "speaker_name": self.speaker_name,
            "text": self.text,
            "timestamp": self.timestamp.isoformat(),
            "confidence": self.confidence,
        }
