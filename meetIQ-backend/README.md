# MeetIQ Backend

MeetIQ is a stateless FastAPI backend that accepts meeting audio, transcribes it, and uses an agent to return a JSON-only response containing a concise summary, action items, and any follow-up date mentioned.

## Run Locally

1. Create and activate a Python 3.10+ environment.
2. Ensure ffmpeg is installed (required by Whisper for audio decoding).
2. Install dependencies:

pip install -r requirements.txt

3. Start the server:

uvicorn main:app --reload

## Environment Variables

- GEMINI_API_KEY: API key for Google Gemini
- GOOGLE_API_KEY: Alternate env var supported by google-adk
- GEMINI_MODEL: Model name (default: gemini-2.5-flash)
- STT_FALLBACK_PLACEHOLDER: Return a demo transcript when Whisper yields empty (default: true)

## Sample Request

curl -X POST "http://127.0.0.1:8000/meetings/process" \
  -F "meeting_id=abc-123" \
  -F "audio_file=@/path/to/meeting.m4a"
