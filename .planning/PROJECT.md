# Linkless

## What This Is

A mobile app that uses Bluetooth Low Energy to detect when two users are physically near each other and automatically records, transcribes, and summarizes their conversation. Users can revisit past conversations on an interactive map showing where and with whom they spoke, and optionally connect via social links. Built for students who meet people in classes, clubs, and events -- but useful for anyone networking in person.

## Core Value

When two Linkless phones are near each other, the conversation is captured, transcribed, and saved automatically with zero user effort -- so no connection is ever forgotten.

## Current State

**Shipped:** v1 MVP (2026-02-21)
**Codebase:** ~22,000 LOC (17,300 Dart + 4,700 Python) across 352 files
**Tech stack:** Flutter 3.29.3 / Dart 3.7.2, FastAPI, PostgreSQL+PostGIS, Tigris, Deepgram+OpenAI, Mapbox, Twilio

**What works:**
- Phone number auth with SMS OTP and persistent JWT sessions
- User profiles with photo, social links, and anonymous mode
- BLE proximity detection with background scanning (iOS + Android)
- Passive audio recording (auto-start on proximity, auto-stop on separation)
- Cloud transcription with speaker diarization and AI summaries
- Interactive map with face-pin markers and date navigation
- Social connection with mutual-accept pattern and link exchange
- Full-text search across conversations
- Privacy controls (invisible mode, user blocking)

**Known tech debt:**
- GATT server hosting stubbed (flutter_ble_peripheral limitation)
- Physical device testing needed for BLE, audio, and transcription
- Block user button not wired to UI (provider exists)
- Mapbox tokens require manual configuration

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

### Active

- [ ] Debug and fix transcription pipeline (recordings failing on Fly.io backend)
- [ ] Manual audio recording in debug panel (record without BLE proximity)
- [ ] Audio playback in debug panel (listen to recordings inline)
- [ ] Working force-transcribe button with proper error reporting
- [ ] AI API connection verification (test OpenAI/xAI keys from debug panel)
- [ ] AI chat interface in debug panel (interact with AI, test summarization)

### Out of Scope

- Group conversations (3+ people) -- complexity too high for v1, defer to v2
- On-device transcription -- cloud is simpler and more accurate for v1
- OAuth/social login -- phone number auth is sufficient and mobile-native
- Web app -- mobile-only for v1
- Real-time chat/messaging -- this is a passive capture tool, not a messenger
- Video recording -- audio-only for v1
- Push notifications -- deferred to v2, not critical for core flow
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

## Constraints

- **Mobile framework**: Flutter 3.29.3 / Dart 3.7.2 -- cross-platform BLE support
- **Backend**: FastAPI (Python) -- async, containerized with Docker
- **Database**: PostgreSQL with PostGIS -- relational data + spatial queries
- **Object storage**: Tigris (Fly.io native, S3-compatible) -- audio file storage
- **Transcription**: Deepgram Nova-3 primary, OpenAI gpt-4o-transcribe fallback
- **AI summaries**: OpenAI gpt-4o-mini
- **SMS auth**: Twilio Verify
- **Maps**: Mapbox Maps SDK for Flutter
- **Hosting**: Fly.io -- FastAPI container + Fly Postgres + Tigris storage
- **Containerization**: Docker Compose for local dev (API, Postgres, Redis, Worker)

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Flutter over React Native | Better native BLE integration, cleaner platform channels for hardware-heavy app | Good -- BLE dual-role scanning works across iOS and Android |
| PostgreSQL + PostGIS over NoSQL | Relational fits user/conversation data; PostGIS enables spatial map queries | Good -- spatial queries power map pins and date filtering |
| Cloud transcription over on-device | Better accuracy, simpler mobile app, multi-provider flexibility | Good -- Deepgram Nova-3 with OpenAI fallback works well |
| Phone number auth over email/OAuth | Mobile-native, lower friction for student audience | Good -- Twilio Verify with JWT refresh rotation |
| Fly.io over AWS/GCP | Simpler container deploys, built-in Postgres and Tigris, good for early stage | Pending -- not yet deployed to production |
| Both phones record independently | Simpler than negotiated recording, each user owns their data | Good -- avoids coordination complexity |
| BLE disconnect = conversation end | Fully passive UX, no manual intervention needed | Good -- 5s staleness check + 5s debounce = ~15s stop latency |
| V1 pairs only | Reduces BLE coordination complexity, group support deferred | Good -- pairwise detection works reliably |
| Drift SQLite for local storage | Reactive queries, type-safe, works offline | Good -- powers conversation list and sync engine |
| Deepgram over OpenAI Whisper | Better speaker diarization, Nova-3 accuracy | Good -- diarization labels map to speakers |
| Mapbox over Google Maps | Better custom marker support, face-pin rendering via Canvas | Good -- dual-mode rendering (pins + clustering) |
| Dual-mode map rendering | PointAnnotations for <=20 pins, GeoJSON clustering for >20 | Good -- handles both sparse and dense days |
| Boto3 pinned to 1.35.95 | 1.36.0+ breaks Tigris uploads (MissingContentLength) | Revisit -- check if Tigris fixes this upstream |
| Drift 2.28.0 pinned | source_gen 2.x compatibility with riverpod_generator 2.6.5 | Revisit -- upgrade requires Riverpod 3.x / Dart 3.9+ |

## Current Milestone: v1.1 Transcription & AI Pipeline

**Goal:** Make the transcription and AI summarization pipeline work end-to-end, with debug tooling to verify and test each component.

**Target features:**
- Fix broken transcription pipeline (all recordings currently fail to transcribe)
- Manual recording + playback in debug panel
- Working force-transcribe with error visibility
- AI API health checks and test chat interface

---
*Last updated: 2026-02-21 after starting milestone v1.1*
