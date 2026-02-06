# LinkLess

**Connect in person, remember forever.**

LinkLess is a mobile app that uses Bluetooth Low Energy (BLE) to detect when two users are physically near each other, automatically records and transcribes their conversation, and saves it for future reference — along with the other person's profile and social links.

Built for students who want to remember the people they meet and the ideas they discuss.

## How It Works

1. **Sign up** and set up your profile (name, photo, bio, social links)
2. **Choose your privacy** — be public or stay anonymous
3. **Open the app** and it starts scanning for nearby LinkLess users via BLE
4. **When two users are within ~2-3 meters**, the app automatically:
   - Detects the other person via Bluetooth Low Energy
   - Creates an "encounter" linking both users
   - Starts recording audio from the microphone
   - Sends audio chunks to the backend for AI transcription
5. **When users move apart**, recording stops and the encounter is saved
6. **AI summarization** extracts topics and key points from the conversation
7. **View past encounters** with full transcripts, summaries, and the other person's profile/socials
8. **Connect on socials** — if the other user is public, tap through to their Instagram, Twitter/X, LinkedIn, GitHub, or website

## Architecture

```
├── mobile/              # Flutter app (iOS + Android)
│   └── lib/
│       ├── main.dart                  # App entry point
│       ├── app/router.dart            # Navigation
│       ├── config/app_config.dart     # Constants
│       ├── models/                    # Data models
│       │   ├── user_model.dart        # User, SocialLinks, PrivacyMode
│       │   └── encounter_model.dart   # Encounter, TranscriptSegment
│       ├── services/                  # Business logic
│       │   ├── api_client.dart        # Backend API communication
│       │   ├── auth_service.dart      # Authentication & session mgmt
│       │   ├── ble_proximity_service.dart  # BLE scanning & proximity
│       │   ├── transcription_service.dart  # Audio recording & upload
│       │   └── encounter_orchestrator.dart # Ties BLE + transcription
│       └── screens/                   # UI
│           ├── auth/                  # Login, Register
│           ├── home/                  # BLE scanning, nearby users
│           ├── encounters/            # List & detail views
│           ├── profile/               # View & edit profile
│           └── settings/              # App settings
│
├── backend/             # Python FastAPI backend
│   ├── app/
│   │   ├── main.py              # FastAPI app, CORS, router mounting
│   │   ├── config.py            # Settings from environment variables
│   │   ├── database.py          # SQLAlchemy async setup
│   │   ├── models.py            # DB models (User, Encounter, Transcript)
│   │   ├── schemas.py           # Pydantic request/response schemas
│   │   ├── auth_utils.py        # JWT, password hashing, auth deps
│   │   ├── ai/
│   │   │   ├── __init__.py
│   │   │   └── provider.py      # Multi-provider AI abstraction
│   │   └── routers/
│   │       ├── auth.py           # Register, login, refresh, logout
│   │       ├── users.py          # Profile CRUD, photo upload
│   │       ├── encounters.py     # Encounter lifecycle
│   │       └── transcription.py  # Audio upload, transcription, summarization
│   ├── requirements.txt
│   └── .env.example
```

## Tech Stack

### Mobile (Flutter)
- **Framework**: Flutter 3.16+ with Dart
- **State Management**: Riverpod
- **BLE**: flutter_blue_plus (Bluetooth Low Energy scanning)
- **Audio**: record (microphone recording)
- **Networking**: Dio (HTTP), WebSocket
- **Storage**: sqflite (local), flutter_secure_storage (tokens)
- **UI**: Material 3, Google Fonts

### Backend (Python)
- **Framework**: FastAPI with async support
- **Database**: SQLAlchemy 2.0 async (SQLite dev / PostgreSQL prod)
- **Auth**: JWT (python-jose) + bcrypt password hashing
- **AI Providers**:
  - **OpenAI** — Whisper (transcription) + GPT-4o (summarization)
  - **Anthropic** — Claude (summarization)
  - **Google** — Gemini 1.5 Pro (transcription + summarization)
  - **xAI** — Grok (summarization)

## Setup

### Backend

```bash
cd backend
python -m venv venv
source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your API keys
uvicorn app.main:app --reload
```

The API will be available at `http://localhost:8000`. See docs at `http://localhost:8000/docs`.

### Mobile

```bash
cd mobile
flutter pub get
flutter run
```

For iOS, also run:
```bash
cd ios && pod install && cd ..
```

### AI Provider Configuration

Set `AI_PROVIDER` in your `.env` to choose which AI service to use:

| Provider | Transcription | Summarization | Key Required |
|----------|--------------|---------------|-------------|
| `openai` | Whisper | GPT-4o | `OPENAI_API_KEY` |
| `anthropic` | Whisper (fallback) | Claude | `ANTHROPIC_API_KEY` + `OPENAI_API_KEY` |
| `google` | Gemini | Gemini | `GOOGLE_API_KEY` |
| `xai` | Whisper (fallback) | Grok | `XAI_API_KEY` + `OPENAI_API_KEY` |

## Privacy Model

Users choose between two modes:

- **Public**: Name, photo, bio, and social links are visible to encounter partners
- **Anonymous**: Others see "Anonymous User" with no identifying information

Users can switch modes at any time. The privacy setting is enforced server-side — the API strips personal data from responses when a user is anonymous.

## API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| POST | `/v1/auth/register` | Register new account |
| POST | `/v1/auth/login` | Login |
| POST | `/v1/auth/refresh` | Refresh token |
| GET | `/v1/users/me` | Get current profile |
| PUT | `/v1/users/me` | Update profile |
| POST | `/v1/users/me/photo` | Upload profile photo |
| GET | `/v1/users/{id}` | Get user's public profile |
| POST | `/v1/encounters` | Create encounter |
| GET | `/v1/encounters` | List encounters |
| GET | `/v1/encounters/{id}` | Get encounter detail |
| POST | `/v1/encounters/{id}/end` | End encounter |
| POST | `/v1/encounters/{id}/transcribe` | Upload audio chunk |
| POST | `/v1/encounters/{id}/summarize` | Generate AI summary |

## License

MIT
