# Linkless

## What This Is

A mobile app that uses Bluetooth Low Energy to detect when two users are physically near each other and automatically records, transcribes, and summarizes their conversation. Users can revisit past conversations on an interactive map showing where and with whom they spoke, and optionally connect via social links. Built for students who meet people in classes, clubs, and events -- but useful for anyone networking in person.

## Core Value

When two Linkless phones are near each other, the conversation is captured, transcribed, and saved automatically with zero user effort -- so no connection is ever forgotten.

## Current State

**Shipped:** v1.1 Transcription & AI Pipeline (2026-02-23)
**Codebase:** ~25,200 LOC (18,900 Dart + 6,300 Python) across 36 modified files in v1.1
**Tech stack:** Flutter 3.29.3 / Dart 3.7.2, FastAPI, PostgreSQL+PostGIS, Tigris, OpenAI Whisper, xAI Grok, Mapbox, Twilio, Upstash Redis, ARQ

**What works:**
- Phone number auth with SMS OTP and persistent JWT sessions
- User profiles with photo, social links, and anonymous mode
- BLE proximity detection with background scanning (iOS + Android)
- Passive audio recording (auto-start on proximity, auto-stop on separation)
- Cloud transcription pipeline on Fly.io (ARQ worker, Redis queue, auto-retry)
- AI summarization with xAI Grok (casual friend-recap tone, topic extraction)
- Interactive map with face-pin markers and date navigation
- Social connection with mutual-accept pattern and link exchange
- Full-text search across conversations
- Privacy controls (invisible mode, user blocking)
- Debug panel: manual recording, playback, health checks, error visibility, force-retranscribe, AI chat

**Known tech debt:**
- GATT server hosting stubbed (flutter_ble_peripheral limitation)
- Physical device testing needed for BLE, audio, and transcription
- Block user button not wired to UI (provider exists)
- Mapbox tokens require manual configuration
- sync_engine.dart does not match summarization_failed status (debug panel cosmetic gap)
- fly.toml lacks dedicated [[vm]] block for worker process group (working but ambiguous)

## Requirements

### Validated

- Phone number signup with SMS verification -- v1
- User profile with photo, name, and social links (Instagram, LinkedIn, X, Snapchat) -- v1
- Anonymous mode: toggle to hide name (shows initials), photo always visible -- v1
- BLE proximity detection between two Linkless phones -- v1
- Auto-start audio recording when two phones detect each other -- v1
- Auto-stop recording when BLE connection is lost (phones move apart) -- v1
- Cloud-based audio transcription via AI APIs -- v1
- AI-generated conversation summary alongside full transcript -- v1
- GPS location capture during recording -- v1
- Map-based conversation history with face pins at conversation locations -- v1
- Date navigation (today + chevron arrows to browse by day) -- v1
- Search across conversations by person, topic, or keyword -- v1
- Social link sharing (opt-in per platform) -- v1
- Device-first storage with cloud backup -- v1
- V1 is 1-on-1 conversations only (pairwise) -- v1
- ARQ worker deployed and running on Fly.io alongside web process -- v1.1
- Redis provisioned on Fly.io with ARQ pool connecting at startup -- v1.1
- Audio format corrected to M4A for OpenAI Whisper compatibility -- v1.1
- xAI Grok model ID fixed to valid identifier -- v1.1
- All required API keys verified on Fly.io -- v1.1
- Health check endpoint with component-level status (Redis, Tigris, ARQ, API keys) -- v1.1
- Error details exposed on failed conversation API responses -- v1.1
- Force-retranscribe endpoint with stage-aware re-enqueue -- v1.1
- Debug-gated AI chat endpoint for interactive testing -- v1.1
- Manual recording from debug panel without BLE proximity -- v1.1
- Inline audio playback in debug panel -- v1.1
- Force-transcribe with visible error details -- v1.1
- Backend health check display in debug panel -- v1.1
- AI connectivity test from debug panel -- v1.1
- AI chat interface in debug panel -- v1.1

### Active

- [ ] Physical device validation (two-phone BLE proximity test)
- [ ] App Store preparation and submission
- [ ] Push notifications for new connections and completed transcriptions

### Out of Scope

- Group conversations (3+ people) -- complexity too high for v1, defer to v2
- On-device transcription -- cloud is simpler and more accurate for v1
- OAuth/social login -- phone number auth is sufficient and mobile-native
- Web app -- mobile-only for v1
- Real-time chat/messaging -- this is a passive capture tool, not a messenger
- Video recording -- audio-only for v1
- Always-on continuous recording -- battery drain, storage costs, privacy concerns

## Context

- Primary audience is students: campus networking, club events, hackathons, career fairs
- Secondary audience is anyone meeting people in person (conferences, meetups)
- Privacy-sensitive: users control what they share (anonymous mode, social link approval)
- BLE background scanning is critical -- app must detect proximity even when not actively open
- Both phones record independently; each user gets their own copy of the transcript
- Recording is fully passive (auto-start, auto-stop) -- zero friction is the core experience
- Two-party consent laws in 13+ US states require mutual consent handshake before any recording
- App Store rejection risk for background microphone usage -- uses foreground-initiated, background-continued pattern
- Transcription pipeline deployed on Fly.io with ARQ worker processing jobs from Redis queue
- Debug panel provides full pipeline observability without SSH access

## Constraints

- **Mobile framework**: Flutter 3.29.3 / Dart 3.7.2 -- cross-platform BLE support
- **Backend**: FastAPI (Python) -- async, containerized with Docker
- **Database**: PostgreSQL with PostGIS -- relational data + spatial queries
- **Object storage**: Tigris (Fly.io native, S3-compatible) -- audio file storage
- **Transcription**: OpenAI Whisper (plain text output, M4A format)
- **AI summaries**: xAI Grok (grok-4-1-fast-non-reasoning, casual friend-recap prompt)
- **SMS auth**: Twilio Verify
- **Maps**: Mapbox Maps SDK for Flutter
- **Hosting**: Fly.io -- FastAPI container (web + worker process groups) + Fly Postgres + Tigris + Upstash Redis
- **Job queue**: ARQ with Redis -- async transcription and summarization pipeline
- **Containerization**: Docker Compose for local dev (API, Postgres, Redis, Worker)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Flutter over React Native | Better native BLE integration, cleaner platform channels for hardware-heavy app | Good -- BLE dual-role scanning works across iOS and Android |
| PostgreSQL + PostGIS over NoSQL | Relational fits user/conversation data; PostGIS enables spatial map queries | Good -- spatial queries power map pins and date filtering |
| Cloud transcription over on-device | Better accuracy, simpler mobile app, multi-provider flexibility | Good -- OpenAI Whisper with plain text output works reliably |
| Phone number auth over email/OAuth | Mobile-native, lower friction for student audience | Good -- Twilio Verify with JWT refresh rotation |
| Fly.io over AWS/GCP | Simpler container deploys, built-in Postgres and Tigris, good for early stage | Good -- web + worker process groups deployed, pipeline running |
| Both phones record independently | Simpler than negotiated recording, each user owns their data | Good -- avoids coordination complexity |
| BLE disconnect = conversation end | Fully passive UX, no manual intervention needed | Good -- 5s staleness check + 5s debounce = ~15s stop latency |
| V1 pairs only | Reduces BLE coordination complexity, group support deferred | Good -- pairwise detection works reliably |
| Drift SQLite for local storage | Reactive queries, type-safe, works offline | Good -- powers conversation list and sync engine |
| Mapbox over Google Maps | Better custom marker support, face-pin rendering via Canvas | Good -- dual-mode rendering (pins + clustering) |
| Dual-mode map rendering | PointAnnotations for <=20 pins, GeoJSON clustering for >20 | Good -- handles both sparse and dense days |
| Boto3 pinned to 1.35.95 | 1.36.0+ breaks Tigris uploads (MissingContentLength) | Revisit -- check if Tigris fixes this upstream |
| Drift 2.28.0 pinned | source_gen 2.x compatibility with riverpod_generator 2.6.5 | Revisit -- upgrade requires Riverpod 3.x / Dart 3.9+ |
| Plain text Whisper output | No JSON segment parsing needed, simpler storage | Good -- transcript stored as plain text string |
| Upstash Redis for ARQ | Pay-as-you-go, minimal ops, dfw region colocation | Good -- reliable job queue, no maintenance overhead |
| require_debug_mode returns 404 | Hides debug endpoint existence in production | Good -- retranscribe and AI chat both use same pattern |
| debug_ peerId prefix convention | Tags debug recordings without DB migration | Good -- simple filtering, no schema changes |
| Shared SUMMARIZATION_SYSTEM_PROMPT | Single source of truth for production and debug AI chat | Good -- debug chat tests exact production behavior |
| Buffer-based SSE parsing | Handles partial UTF-8 chunks from Dio streams | Good -- reliable token-by-token streaming display |

---
*Last updated: 2026-02-23 after v1.1 milestone*
