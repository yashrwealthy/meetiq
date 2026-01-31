# MeetIQ - Intelligent Meeting Assistant

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter"/>
  <img src="https://img.shields.io/badge/FastAPI-009688?style=for-the-badge&logo=fastapi&logoColor=white" alt="FastAPI"/>
  <img src="https://img.shields.io/badge/Python-3776AB?style=for-the-badge&logo=python&logoColor=white" alt="Python"/>
  <img src="https://img.shields.io/badge/Google%20Gemini-4285F4?style=for-the-badge&logo=google&logoColor=white" alt="Gemini"/>
  <img src="https://img.shields.io/badge/Whisper-000000?style=for-the-badge&logo=openai&logoColor=white" alt="Whisper"/>
</p>

MeetIQ is an AI-powered meeting intelligence platform designed for **wealth management professionals**. It transforms meeting recordings into actionable insights, helping financial advisors maintain stronger client relationships through intelligent analysis, risk assessment, and automated follow-up generation.

---

## 🎯 Key Features

### 📱 Mobile App (Flutter)
- **Voice Recording** - Record meetings directly from the app with real-time audio visualization
- **Chunk-based Upload** - Reliable uploads with automatic resume for large recordings
- **Meeting Summaries** - AI-generated summaries with key points and discussion topics
- **Action Items** - Automatically extracted tasks with due dates and priorities
- **Follow-up Scheduling** - Calendar integration for scheduling follow-up meetings
- **Client Portfolio** - View client information, risk profiles, and meeting history
- **Email Draft Generation** - AI-crafted follow-up emails ready to send via Gmail/Outlook
- **Client Risk Assessment** - Real-time risk analysis and pitch preparation insights

### 🖥️ Backend (FastAPI + AI)
- **Speech-to-Text** - OpenAI Whisper for accurate transcription
- **AI Analysis** - Google Gemini for intelligent meeting analysis
- **Async Processing** - ARQ worker queue for background processing
- **Client Memory** - Persistent client profiles with cumulative meeting insights
- **Email Generation** - Context-aware professional email drafts
- **S3/Local Storage** - Flexible storage options for recordings and results

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              MeetIQ Mobile App                               │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐      │
│  │  Record  │  │  Upload  │  │ Meetings │  │ Summary  │  │  Client  │      │
│  │  Screen  │→ │  Screen  │→ │   List   │→ │  Detail  │  │ Profile  │      │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘      │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            FastAPI Backend (V2)                              │
│  ┌──────────────────┐  ┌──────────────────┐  ┌──────────────────┐          │
│  │  Upload Chunks   │  │   Job Status     │  │   Email Draft    │          │
│  │  POST /upload    │  │   GET /status    │  │   POST /draft    │          │
│  └────────┬─────────┘  └────────┬─────────┘  └────────┬─────────┘          │
│           │                     │                     │                     │
│           ▼                     ▼                     ▼                     │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │                        Services Layer                             │      │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐              │      │
│  │  │ Storage │  │  Audio  │  │  Redis  │  │   S3    │              │      │
│  │  │ Service │  │ Service │  │  Queue  │  │ Storage │              │      │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘              │      │
│  └──────────────────────────────────────────────────────────────────┘      │
│           │                                                                 │
│           ▼                                                                 │
│  ┌──────────────────────────────────────────────────────────────────┐      │
│  │                          AI Agents                                │      │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐   │      │
│  │  │ OpenAI Whisper  │  │ Gemini Analysis │  │ Email Draft Gen │   │      │
│  │  │  Transcription  │  │   Agent (ADK)   │  │      Agent      │   │      │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘   │      │
│  └──────────────────────────────────────────────────────────────────┘      │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## 📦 Project Structure

```
meetiq/
├── meetIQ-mobile/           # Flutter mobile application
│   ├── lib/
│   │   ├── controllers/     # GetX state management
│   │   ├── models/          # Data models (Meeting, ActionItem, EmailDraft, etc.)
│   │   ├── screens/         # UI screens
│   │   │   ├── record_screen.dart          # Audio recording
│   │   │   ├── upload_screen.dart          # Chunk upload progress
│   │   │   ├── recordings_list_screen.dart # Meeting list
│   │   │   ├── recording_detail_screen.dart # Summary & insights
│   │   │   └── client_profile_screen.dart  # Portfolio & risk
│   │   ├── services/        # API & platform services
│   │   ├── utils/           # Helpers & utilities
│   │   └── widgets/         # Reusable UI components
│   └── pubspec.yaml
│
├── meetIQ-backend/          # FastAPI backend server
│   ├── v2/                  # Version 2 API
│   │   ├── api/
│   │   │   ├── meetings.py          # Upload, status, memory endpoints
│   │   │   └── meetings_gemini.py   # AI processing endpoints
│   │   ├── agents/
│   │   │   └── email_draft_agent.py # Email generation AI
│   │   ├── models/
│   │   │   └── schemas.py           # Pydantic models
│   │   ├── services/
│   │   │   └── storage.py           # S3/local storage
│   │   └── worker.py                # ARQ background worker
│   ├── services/            # Shared services
│   │   └── audio_service.py # FFmpeg, Whisper integration
│   ├── main.py              # FastAPI app entry
│   ├── worker.py            # ARQ worker entry
│   └── requirements.txt
│
└── README.md
```

---

## 🚀 Getting Started

### Prerequisites

- **Python 3.10+**
- **Flutter 3.2+**
- **FFmpeg** (required by Whisper for audio decoding)
- **Redis** (for job queue)
- **Conda** (recommended for Python environment)

### Backend Setup

```bash
# Navigate to backend directory
cd meetIQ-backend

# Create and activate conda environment
conda create -n meetiq python=3.10
conda activate meetiq

# Install dependencies
pip install -r requirements.txt

# Set environment variables
export GEMINI_API_KEY=your_gemini_api_key
export AWS_ACCESS_KEY_ID=your_aws_key        # Optional: for S3 storage
export AWS_SECRET_ACCESS_KEY=your_aws_secret # Optional: for S3 storage

# Start Redis server (in separate terminal)
redis-server

# Start ARQ worker (in separate terminal)
arq worker.WorkerSettings

# Start FastAPI server
uvicorn main:app --host 0.0.0.0 --port 8004 --reload
```

### Mobile App Setup

```bash
# Navigate to mobile directory
cd meetIQ-mobile

# Install Flutter dependencies
flutter pub get

# Run on iOS Simulator
flutter run -d ios

# Run on Android Emulator
flutter run -d android

# Run on Web (Chrome)
flutter run -d chrome

# Build for production (Web)
flutter build web --release
```

---

## 🔌 API Endpoints

### V2 Meetings API

| Method | Endpoint | Description |
|--------|----------|-------------|
| `POST` | `/v2/meetings/upload_chunk` | Upload audio chunk |
| `GET` | `/v2/meetings/ack` | Verify upload completion |
| `GET` | `/v2/meetings/status` | Get job processing status |
| `GET` | `/v2/meetings/memory` | Get client memory/history |
| `POST` | `/v2/email/draft` | Generate email draft |
| `GET` | `/clients/{id}/overview` | Get client risk assessment |

### Sample Requests

**Upload Audio Chunk:**
```bash
curl -X POST "http://localhost:8004/v2/meetings/upload_chunk" \
  -F "client_id=user-123" \
  -F "meeting_id=meeting-456" \
  -F "chunk_id=0" \
  -F "total_chunks=5" \
  -F "file=@chunk_0.m4a"
```

**Check Job Status:**
```bash
curl "http://localhost:8004/v2/meetings/status?job_id=v2-merge-user-123-meeting-456"
```

**Generate Email Draft:**
```bash
curl -X POST "http://localhost:8004/v2/email/draft" \
  -H "Content-Type: application/json" \
  -d '{
    "job_id": "v2-merge-user-123-meeting-456",
    "client_name": "John Smith",
    "partner_name": "Wealthy-Partner"
  }'
```

---

## 🤖 AI Models

### Transcription
- **OpenAI Whisper** - State-of-the-art speech recognition
- Supports multiple audio formats (M4A, WAV, MP3)
- Automatic language detection

### Analysis & Generation
- **Google Gemini 2.5 Flash** - Fast, intelligent analysis
- Meeting summarization with key points
- Action item extraction with deadlines
- Follow-up date detection
- Sentiment analysis
- Risk assessment

### Email Draft Generation
- Context-aware professional emails
- Personalized based on meeting content
- Suggested attachments
- Configurable tone (professional, friendly, formal)

---

## 📊 Data Models

### Meeting Insight
```json
{
  "summary": "Discussed retirement planning strategies...",
  "key_points": ["401k rollover options", "Estate planning timeline"],
  "action_items": [
    {
      "task": "Send retirement projections",
      "owner": "Partner",
      "due_date": "2026-02-07"
    }
  ],
  "follow_up": {
    "suggested_date": "2026-02-15",
    "agenda_items": ["Review updated portfolio", "Discuss tax implications"]
  },
  "sentiment": "positive",
  "confidence_score": 0.92
}
```

### Email Draft
```json
{
  "job_id": "v2-merge-user-123-meeting-456",
  "status": "success",
  "subject": "Follow-up: Our Retirement Planning Discussion",
  "body": "Dear John,\n\nThank you for meeting with me today...",
  "suggested_attachments": ["retirement_projections.pdf"],
  "tone": "professional"
}
```

---

## 🎨 Screenshots

| Recording | Processing | Summary |
|-----------|------------|---------|
| Voice recording with real-time waveform | AI analysis in progress | Meeting insights & actions |

| Email Draft | Client Profile | Risk Assessment |
|-------------|----------------|-----------------|
| AI-generated follow-up email | Portfolio overview | Client risk analysis |

---

## 🛠️ Technology Stack

### Mobile
| Technology | Purpose |
|------------|---------|
| Flutter 3.2+ | Cross-platform UI framework |
| GetX | State management & dependency injection |
| GoRouter | Declarative navigation |
| Record | Audio recording |
| AudioPlayers | Audio playback |
| URL Launcher | External app integration (email, calendar) |

### Backend
| Technology | Purpose |
|------------|---------|
| FastAPI | High-performance API framework |
| Pydantic | Data validation & serialization |
| ARQ | Async job queue (Redis-backed) |
| OpenAI Whisper | Speech-to-text transcription |
| Google Gemini | LLM for analysis & generation |
| Boto3 | AWS S3 integration |

---

## 🔒 Environment Variables

### Backend (.env)
```env
# AI Services
GEMINI_API_KEY=your_gemini_api_key
GEMINI_MODEL=gemini-2.5-flash

# Storage (Optional - defaults to local)
USE_S3=false
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret
S3_BUCKET_NAME=meetiq-uploads

# Redis
REDIS_URL=redis://localhost:6379

# Server
HOST=0.0.0.0
PORT=8004
```

### Mobile
Configure the API base URL in `upload_controller.dart`:
```dart
static const String baseUrl = 'http://YOUR_SERVER_IP:8004/v2';
```

---

## 📈 Roadmap

- [ ] Real-time transcription during recording
- [ ] Multi-language support
- [ ] Team collaboration features
- [ ] CRM integrations (Salesforce, HubSpot)
- [ ] Calendar sync (Google, Outlook)
- [ ] Advanced analytics dashboard
- [ ] Voice notes with instant insights
- [ ] Offline mode with sync

---

## 🤝 Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is proprietary software. All rights reserved.

---

## 👥 Team

Built with ❤️ for wealth management professionals

---

<p align="center">
  <b>MeetIQ</b> - Transform meetings into opportunities
</p>
