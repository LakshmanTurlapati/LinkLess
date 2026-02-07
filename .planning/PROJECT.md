# Linkless

## What This Is

A mobile app that uses Bluetooth Low Energy to detect when two users are physically near each other and automatically records, transcribes, and summarizes their conversation. Users can revisit past conversations on an interactive map showing where and with whom they spoke, and optionally connect via social links. Built for students who meet people in classes, clubs, and events -- but useful for anyone networking in person.

## Core Value

When two Linkless phones are near each other, the conversation is captured, transcribed, and saved automatically with zero user effort -- so no connection is ever forgotten.

## Requirements

### Validated

(None yet -- ship to validate)

### Active

- [ ] Phone number signup with SMS verification
- [ ] User profile with photo, name, and social links (Instagram, LinkedIn, X, Snapchat)
- [ ] Anonymous mode: toggle to hide name (shows initials), photo always visible
- [ ] BLE proximity detection between two Linkless phones
- [ ] Auto-start audio recording when two phones detect each other
- [ ] Auto-stop recording when BLE connection is lost (phones move apart)
- [ ] Cloud-based audio transcription via AI APIs
- [ ] AI-generated conversation summary alongside full transcript
- [ ] GPS location capture during recording
- [ ] Map-based conversation history with face pins at conversation locations
- [ ] Date navigation (today + chevron arrows to browse by day)
- [ ] Search across conversations by person, topic, or keyword
- [ ] Social link sharing (opt-in per platform)
- [ ] Device-first storage with cloud backup
- [ ] V1 is 1-on-1 conversations only (pairwise)

### Out of Scope

- Group conversations (3+ people) -- complexity too high for v1, defer to v2
- On-device transcription -- cloud is simpler and more accurate for v1
- OAuth/social login -- phone number auth is sufficient and mobile-native
- Web app -- mobile-only for v1
- Real-time chat/messaging -- this is a passive capture tool, not a messenger
- Video recording -- audio-only for v1

## Context

- Primary audience is students: campus networking, club events, hackathons, career fairs
- Secondary audience is anyone meeting people in person (conferences, meetups)
- Privacy-sensitive: users control what they share (anonymous mode, social link approval)
- BLE background scanning is critical -- app must detect proximity even when not actively open
- Both phones record independently; each user gets their own copy of the transcript
- Recording is fully passive (auto-start, auto-stop) -- zero friction is the core experience

## Constraints

- **Mobile framework**: Flutter -- best native integration for BLE-heavy apps, cross-platform (iOS + Android)
- **Backend**: FastAPI (Python) -- async, performant, containerized
- **Database**: PostgreSQL with PostGIS -- relational data + spatial queries for map features
- **Object storage**: Tigris (Fly.io native, S3-compatible) -- audio file storage
- **Transcription**: Multi-provider AI (OpenAI Whisper primary, with support for Google, Anthropic, xAI)
- **AI summaries**: Multi-provider LLM support (Anthropic, OpenAI, Google, xAI)
- **SMS auth**: Twilio -- phone number verification
- **Push notifications**: Firebase Cloud Messaging -- cross-platform
- **Maps**: Mapbox or Google Maps SDK in Flutter
- **Hosting**: Fly.io -- FastAPI container + Fly Postgres + Tigris storage
- **Containerization**: Docker for all backend services

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Flutter over React Native | Better native BLE integration, cleaner platform channels for hardware-heavy app | -- Pending |
| PostgreSQL + PostGIS over NoSQL | Relational fits user/conversation data; PostGIS enables spatial map queries | -- Pending |
| Cloud transcription over on-device | Better accuracy, simpler mobile app, multi-provider flexibility | -- Pending |
| Phone number auth over email/OAuth | Mobile-native, lower friction for student audience | -- Pending |
| Fly.io over AWS/GCP | Simpler container deploys, built-in Postgres and Tigris, good for early stage | -- Pending |
| Both phones record independently | Simpler than negotiated recording, each user owns their data | -- Pending |
| BLE disconnect = conversation end | Fully passive UX, no manual intervention needed | -- Pending |
| V1 pairs only | Reduces BLE coordination complexity, group support deferred | -- Pending |

---
*Last updated: 2026-02-07 after initialization*
