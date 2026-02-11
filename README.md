<p align="center">
  <img src="assets/app%20icon.png" alt="LinkLess" width="120" />
</p>

<h1 align="center">LinkLess</h1>

<p align="center">
  <em>Never forget a connection.</em>
</p>

<p align="center">
  A mobile app that runs in your pocket — detecting nearby people via Bluetooth, recording and transcribing your conversations with AI, and pinning every encounter to a map you can revisit anytime.
</p>

<p align="center">
  <a href="https://github.com/LakshmanTurlapati/LinkLess/stargazers">
    <img src="https://img.shields.io/github/stars/LakshmanTurlapati/LinkLess?style=for-the-badge&color=0a1628&labelColor=162040" alt="Stars" />
  </a>
  <a href="https://github.com/LakshmanTurlapati/LinkLess/network/members">
    <img src="https://img.shields.io/github/forks/LakshmanTurlapati/LinkLess?style=for-the-badge&color=0a1628&labelColor=162040" alt="Forks" />
  </a>
  <a href="https://github.com/LakshmanTurlapati/LinkLess/issues">
    <img src="https://img.shields.io/github/issues/LakshmanTurlapati/LinkLess?style=for-the-badge&color=0a1628&labelColor=162040" alt="Issues" />
  </a>
  <a href="https://github.com/LakshmanTurlapati/LinkLess/commits/main">
    <img src="https://img.shields.io/github/last-commit/LakshmanTurlapati/LinkLess?style=for-the-badge&color=0a1628&labelColor=162040" alt="Last Commit" />
  </a>
</p>

---

## The Problem

You meet someone at a conference, a coffee shop, a party. You have a great conversation — then a week later, you can't remember their name, what you talked about, or how to find them again.

## The Solution

LinkLess runs quietly in your pocket. When two users are nearby, their phones discover each other over **Bluetooth Low Energy**. The app **passively records** the conversation, **transcribes** it with OpenAI Whisper, **summarizes** it with xAI Grok, and **pins it to a map** so you can revisit every encounter — who, what, and where. Want to stay in touch? Send a connection request and exchange socials.

---

## Screenshots

<table>
  <tr>
    <td align="center"><strong>Login</strong></td>
    <td align="center"><strong>Conversations Map</strong></td>
    <td align="center"><strong>Profile View</strong></td>
  </tr>
  <tr>
    <td><img src="assets/UI%20(login).png" alt="Login Screen" width="260" /></td>
    <td><img src="assets/UI%20(Conversations%20map).png" alt="Conversations Map" width="260" /></td>
    <td><img src="assets/UI%20(Profile%20View).png" alt="Profile View" width="260" /></td>
  </tr>
</table>

---

## Features

| | Feature | Description |
|---|---|---|
| 📡 | **BLE Proximity Detection** | Automatically discovers nearby LinkLess users via Bluetooth Low Energy scanning and advertising — no manual pairing needed |
| 🎙️ | **Passive Audio Recording** | Records conversations in the background using a foreground service with configurable audio sessions |
| 🤖 | **AI Transcription & Summarization** | Transcribes audio with OpenAI Whisper, then summarizes key topics with xAI Grok — all asynchronously via an ARQ task queue |
| 🗺️ | **Interactive Map** | Every conversation is GPS-tagged and displayed on a Mapbox map with date-based navigation |
| 🤝 | **Social Connections** | Send connection requests after a conversation; once mutually accepted, exchange Instagram, LinkedIn, X, and Snapchat handles |
| 📴 | **Offline-First** | Local Drift/SQLite database stores conversations, transcripts, and blocked users — syncs to the cloud when connectivity returns |
| 🔍 | **Full-Text Search** | PostgreSQL `tsvector` powered search across transcripts, summaries, and peer names with ranked results and snippet highlights |
| 🔒 | **Privacy Controls** | Anonymous mode hides your identity from peers; invisible mode stops BLE advertising entirely; block users at any time |
| 📱 | **Phone Auth with OTP** | Passwordless authentication via Twilio Verify SMS — no emails, no passwords, just your phone number |

---

## Architecture

### System Overview

```mermaid
graph TB
    subgraph Mobile["📱 Mobile App (Flutter)"]
        BLE[BLE Manager]
        REC[Recording Service]
        SYNC[Sync Engine]
        MAP[Map Screen]
        DB_LOCAL[(Drift/SQLite)]
    end

    subgraph Backend["⚙️ Backend (FastAPI)"]
        API[REST API]
        AUTH[Auth Service]
        CONV[Conversation Service]
        PROF[Profile Service]
        CONN[Connection Service]
    end

    subgraph Workers["🔄 ARQ Workers"]
        TRX[Transcription Task]
        SUM[Summarization Task]
    end

    subgraph DataStores["💾 Data Stores"]
        PG[(PostgreSQL + PostGIS)]
        RD[(Redis)]
        S3[(Tigris S3)]
    end

    subgraph ExternalAPIs["🌐 External APIs"]
        WHISPER[OpenAI Whisper]
        GROK[xAI Grok]
        TWILIO[Twilio Verify]
    end

    BLE -->|Detect peer| REC
    REC -->|Save locally| DB_LOCAL
    SYNC -->|Upload audio| S3
    SYNC -->|Create conversation| API
    API --> AUTH & CONV & PROF & CONN
    AUTH -->|Send OTP| TWILIO
    CONV -->|Enqueue job| RD
    RD -->|Pick up job| TRX
    TRX -->|Download audio| S3
    TRX -->|Transcribe| WHISPER
    TRX -->|Store result| PG
    TRX -->|Chain| SUM
    SUM -->|Summarize| GROK
    SUM -->|Store result| PG
    MAP -->|Fetch map data| API
    API -->|Query| PG
```

### Conversation Lifecycle

```mermaid
sequenceDiagram
    participant U1 as User A (Phone)
    participant U2 as User B (Phone)
    participant API as FastAPI
    participant S3 as Tigris S3
    participant Q as Redis Queue
    participant W as ARQ Worker
    participant AI1 as OpenAI Whisper
    participant AI2 as xAI Grok
    participant DB as PostgreSQL

    U1->>U2: BLE discovery (RSSI > threshold)
    U1->>U1: Start recording audio
    Note over U1,U2: Conversation happens...
    U1->>U1: BLE signal lost → stop recording
    U1->>U1: Save to local Drift DB
    U1->>API: POST /conversations (with GPS coords)
    API->>S3: Generate presigned upload URL
    API-->>U1: Return upload URL + conversation ID
    U1->>S3: PUT audio file (presigned URL)
    U1->>API: POST /conversations/{id}/confirm-upload
    API->>Q: Enqueue transcription job
    Q->>W: Pick up job
    W->>S3: Download audio
    W->>AI1: Send to Whisper API
    AI1-->>W: Return transcript
    W->>DB: Store transcript + search vector
    W->>AI2: Send transcript to Grok
    AI2-->>W: Return summary + key topics
    W->>DB: Store summary, mark completed
    U1->>API: GET /conversations/map?date=...
    API->>DB: Query with PostGIS
    API-->>U1: Return map pins with summaries
```

### BLE Proximity State Machine

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Detected: Peer BLE advertisement received
    Detected --> Connected: RSSI > connection threshold (sustained)
    Detected --> Idle: RSSI too weak / timeout
    Connected --> Recording: Start audio capture
    Recording --> Connected: Audio paused
    Connected --> Disconnecting: RSSI < disconnect threshold (sustained)
    Disconnecting --> Idle: Peer lost → save & upload
    Disconnecting --> Connected: RSSI recovers
```

---

## Tech Stack

<p align="center">
  <strong>Backend</strong><br/>
  <img src="https://img.shields.io/badge/Python-3.12-3776AB?style=flat-square&logo=python&logoColor=white" alt="Python" />
  <img src="https://img.shields.io/badge/FastAPI-0.128-009688?style=flat-square&logo=fastapi&logoColor=white" alt="FastAPI" />
  <img src="https://img.shields.io/badge/PostgreSQL_16-+PostGIS-4169E1?style=flat-square&logo=postgresql&logoColor=white" alt="PostgreSQL" />
  <img src="https://img.shields.io/badge/Redis-7-DC382D?style=flat-square&logo=redis&logoColor=white" alt="Redis" />
  <img src="https://img.shields.io/badge/Fly.io-Deploy-8B5CF6?style=flat-square&logo=flydotio&logoColor=white" alt="Fly.io" />
</p>

<p align="center">
  <strong>Mobile</strong><br/>
  <img src="https://img.shields.io/badge/Flutter-3.7+-02569B?style=flat-square&logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.7+-0175C2?style=flat-square&logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Mapbox-Maps-000000?style=flat-square&logo=mapbox&logoColor=white" alt="Mapbox" />
  <img src="https://img.shields.io/badge/Drift-SQLite-blue?style=flat-square" alt="Drift" />
</p>

<p align="center">
  <strong>AI & Services</strong><br/>
  <img src="https://img.shields.io/badge/OpenAI-Whisper-412991?style=flat-square&logo=openai&logoColor=white" alt="OpenAI Whisper" />
  <img src="https://img.shields.io/badge/xAI-Grok-000000?style=flat-square" alt="xAI Grok" />
  <img src="https://img.shields.io/badge/Twilio-Verify-F22F46?style=flat-square&logo=twilio&logoColor=white" alt="Twilio" />
  <img src="https://img.shields.io/badge/Tigris-S3-FF6600?style=flat-square" alt="Tigris S3" />
</p>

---

## Project Structure

```
LinkLess/
├── assets/                          # Shared design assets & UI mockups
├── resources/                       # Pitch deck and documents
├── docker-compose.yml               # PostgreSQL + Redis + API + Worker
│
├── backend/
│   ├── main.py                      # FastAPI app entry point
│   ├── Dockerfile                   # Multi-stage Python 3.12 build
│   ├── fly.toml                     # Fly.io deployment config
│   ├── requirements.txt             # Pinned Python dependencies
│   ├── alembic.ini                  # Database migration config
│   ├── alembic/versions/            # 6 migration scripts (PostGIS → search vectors)
│   └── app/
│       ├── api/v1/
│       │   ├── router.py            # Aggregates all route modules
│       │   └── routes/
│       │       ├── auth.py          # OTP send/verify, token refresh, logout
│       │       ├── conversations.py # CRUD, map queries, full-text search
│       │       ├── connections.py   # Request/accept/decline, block/unblock
│       │       ├── profile.py       # Profile CRUD, photo presign, social links
│       │       ├── uploads.py       # Generic presigned URL generation
│       │       └── health.py        # Health check endpoint
│       ├── core/
│       │   ├── config.py            # Pydantic Settings (all env vars)
│       │   ├── database.py          # Async SQLAlchemy engine & sessions
│       │   ├── dependencies.py      # FastAPI DI (JWT auth, current user)
│       │   └── security.py          # JWT creation/decoding, password hashing
│       ├── models/                  # SQLAlchemy models (7 tables + PostGIS)
│       ├── schemas/                 # Pydantic request/response schemas
│       ├── services/               # Business logic layer
│       │   ├── auth_service.py      # Twilio OTP + session management
│       │   ├── conversation_service.py
│       │   ├── connection_service.py
│       │   ├── profile_service.py
│       │   ├── storage_service.py   # Tigris/S3 presigned URLs
│       │   ├── transcription_service.py  # OpenAI Whisper integration
│       │   └── summarization_service.py  # xAI Grok integration
│       └── tasks/
│           ├── transcription.py     # ARQ task: transcribe audio
│           ├── summarization.py     # ARQ task: summarize transcript
│           └── worker.py            # ARQ worker config (5 concurrent, 10min timeout)
│
└── mobile/
    ├── pubspec.yaml                 # Flutter dependencies & config
    └── lib/
        ├── main.dart                # App entry point
        ├── app.dart                 # Root widget
        ├── ble/                     # Bluetooth Low Energy
        │   ├── ble_manager.dart     # Central orchestrator
        │   ├── ble_central_service.dart   # BLE scanning
        │   ├── ble_peripheral_service.dart # BLE advertising
        │   ├── proximity_state_machine.dart # State transitions
        │   └── rssi_filter.dart     # Signal strength filtering
        ├── core/
        │   ├── config/app_config.dart     # Runtime config (API URL, Mapbox)
        │   ├── network/dio_client.dart    # HTTP client with auth interceptor
        │   └── theme/               # App colors & theme
        ├── features/
        │   ├── auth/                # Phone OTP login flow
        │   ├── map/                 # Mapbox conversation map + date nav
        │   ├── recording/           # Audio capture, local DB, playback
        │   ├── conversations/       # Conversation list screen
        │   ├── connections/         # Connection requests & social links
        │   ├── profile/             # Profile CRUD, photo upload, encounter cards
        │   ├── search/              # Full-text search UI
        │   └── sync/               # Cloud sync engine & upload service
        └── router/                  # GoRouter navigation
```

---

## API Endpoints

All endpoints are prefixed with `/api/v1`.

### Auth

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/auth/send-otp` | No | Send OTP code to a phone number via Twilio |
| `POST` | `/auth/verify-otp` | No | Verify OTP and receive access/refresh tokens |
| `POST` | `/auth/refresh` | No | Exchange refresh token for new token pair |
| `POST` | `/auth/logout` | Yes | Revoke all refresh tokens for the user |

### Profile

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/profile` | Yes | Create user profile |
| `GET` | `/profile` | Yes | Get current user's profile with social links |
| `PATCH` | `/profile` | Yes | Update profile fields (display name, photo, anonymous mode) |
| `POST` | `/profile/photo/presign` | Yes | Get presigned URL for photo upload |
| `PUT` | `/profile/social-links` | Yes | Replace all social links |
| `GET` | `/profile/social-links` | Yes | Get all social links |

### Conversations

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/conversations` | Yes | Create conversation with GPS coords |
| `POST` | `/conversations/{id}/confirm-upload` | Yes | Confirm audio uploaded, trigger transcription |
| `GET` | `/conversations` | Yes | List all conversations (newest first) |
| `GET` | `/conversations/map?date=YYYY-MM-DD` | Yes | Get conversations for map display on a date |
| `GET` | `/conversations/search?q=...` | Yes | Full-text search across transcripts and summaries |
| `GET` | `/conversations/{id}` | Yes | Get conversation with transcript and summary |

### Connections

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/connections/request` | Yes | Send connection request for a conversation |
| `POST` | `/connections/{id}/accept` | Yes | Accept request; if mutual, exchange socials |
| `POST` | `/connections/{id}/decline` | Yes | Decline a connection request |
| `GET` | `/connections` | Yes | List all established connections |
| `GET` | `/connections/pending` | Yes | List incoming pending requests |
| `GET` | `/connections/status?conversation_id=` | Yes | Check connection status for a conversation |
| `POST` | `/connections/block` | Yes | Block a user |
| `DELETE` | `/connections/block/{user_id}` | Yes | Unblock a user |
| `GET` | `/connections/blocked` | Yes | List blocked users |

### Uploads & Health

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| `POST` | `/uploads/presign` | No | Generate presigned upload URL for Tigris S3 |
| `GET` | `/health` | No | Health check (API + database + PostGIS status) |

---

## Environment Variables

### Backend

| Variable | Default | Description |
|----------|---------|-------------|
| `DATABASE_URL` | `postgresql+asyncpg://linkless:linkless@localhost:5432/linkless` | PostgreSQL connection string |
| `REDIS_URL` | `redis://localhost:6379` | Redis URL for ARQ task queue |
| `JWT_SECRET_KEY` | — | Secret key for HS256 JWT signing |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | `30` | Access token TTL |
| `REFRESH_TOKEN_EXPIRE_DAYS` | `30` | Refresh token TTL |
| `TWILIO_ACCOUNT_SID` | — | Twilio Account SID |
| `TWILIO_AUTH_TOKEN` | — | Twilio Auth Token |
| `TWILIO_VERIFY_SERVICE_SID` | — | Twilio Verify Service SID |
| `TWILIO_TEST_MODE` | `false` | Bypass SMS in development |
| `OPENAI_API_KEY` | — | OpenAI API key (Whisper transcription) |
| `XAI_API_KEY` | — | xAI API key (Grok summarization) |
| `TIGRIS_ENDPOINT` | `https://fly.storage.tigris.dev` | S3-compatible storage endpoint |
| `TIGRIS_BUCKET` | `linkless-audio` | Storage bucket name |
| `AWS_ACCESS_KEY_ID` | — | Tigris access key |
| `AWS_SECRET_ACCESS_KEY` | — | Tigris secret key |

### Mobile (build-time)

| Variable | Default | Description |
|----------|---------|-------------|
| `API_BASE_URL` | `https://linkless-api.fly.dev/api/v1` | Backend API base URL |
| `MAPBOX_ACCESS_TOKEN` | — | Mapbox public token for map rendering |

---

## Getting Started

### Prerequisites

- **Docker** & **Docker Compose** (recommended for backend)
- **Python 3.12+** (if running backend manually)
- **Flutter 3.7+** / Dart 3.7+
- **Xcode** (iOS) or **Android Studio** (Android)

### Clone

```bash
git clone https://github.com/LakshmanTurlapati/LinkLess.git
cd LinkLess
```

### Backend Setup

#### Option A: Docker Compose (recommended)

```bash
cp backend/.env.example backend/.env
# Edit backend/.env with your API keys

docker compose up -d
```

This starts PostgreSQL 16 + PostGIS, Redis 7, the FastAPI server, and the ARQ worker.

#### Option B: Manual

```bash
cd backend
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
# Edit .env with your API keys

# Run database migrations
alembic upgrade head

# Start the API server
uvicorn main:app --reload --port 8000

# In a separate terminal, start the ARQ worker
arq app.tasks.worker.WorkerSettings
```

### Mobile Setup

```bash
cd mobile
flutter pub get
dart run build_runner build --delete-conflicting-outputs

flutter run \
  --dart-define=API_BASE_URL=http://localhost:8000/api/v1 \
  --dart-define=MAPBOX_ACCESS_TOKEN=your_mapbox_token
```

### Verify

```bash
curl http://localhost:8000/api/v1/health
# {"status":"healthy","database":"connected","postgis":"available"}
```

---

## Deployment

The backend is configured for [Fly.io](https://fly.io):

```bash
cd backend
fly launch        # First-time setup
fly deploy        # Deploy updates
```

Key settings from `fly.toml`:

| Setting | Value |
|---------|-------|
| App name | `linkless-api` |
| Region | `dfw` (Dallas-Fort Worth) |
| VM | `shared-cpu-1x`, 256 MB |
| Release command | `alembic upgrade head` |
| Force HTTPS | `true` |
| Auto-stop machines | Enabled |

Attach managed databases:

```bash
fly postgres create
fly redis create
fly storage create   # Tigris S3 bucket
```

---

## Contributing

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feat/your-feature`)
3. **Commit** your changes (`git commit -m "Add your feature"`)
4. **Push** to the branch (`git push origin feat/your-feature`)
5. **Open** a Pull Request

Please follow the existing architectural patterns:
- Backend: route → service → model with Pydantic schemas
- Mobile: feature-based structure with Riverpod providers
- All async/await, no synchronous database calls

---

<p align="center">
  Built by <a href="https://github.com/LakshmanTurlapati">Lakshman Turlapati</a><br/>
  If LinkLess helped you never forget a connection, consider giving it a ⭐
</p>
