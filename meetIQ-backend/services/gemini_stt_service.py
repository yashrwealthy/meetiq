from __future__ import annotations

import os
import time
import json
import asyncio
from typing import Optional, Dict, Any
from pathlib import Path

try:
    from google import genai
    from google.genai import types
    _GENAI_AVAILABLE = True
except ImportError:
    genai = None
    types = None
    _GENAI_AVAILABLE = False


def _get_gemini_client() -> Optional[object]:
    """Initialize and return Gemini client with API key from settings."""
    if not _GENAI_AVAILABLE:
        return None
    
    try:
        from settings import Settings
    except ImportError:
        import sys
        sys.path.append(os.getcwd())
        from settings import Settings
    
    settings = Settings()
    if not settings.gemini_api_key:
        return None
    
    try:
        client = genai.Client(api_key=settings.gemini_api_key)
        return client
    except Exception as e:
        print(f"Failed to initialize Gemini client: {e}")
        return None


def _placeholder_transcript() -> str:
    """Return placeholder transcript for fallback scenarios."""
    return (
        "Placeholder transcript: The team reviewed current progress, discussed blockers, "
        "and agreed on next steps for the upcoming sprint."
    )


def _get_transcription_model() -> str:
    """Get the configured transcription model, defaults to gemini-1.5-flash."""
    try:
        from settings import Settings
    except ImportError:
        import sys
        sys.path.append(os.getcwd())
        from settings import Settings
    
    settings = Settings()
    return getattr(settings, 'gemini_transcription_model', 'gemini-2.5-flash')


async def _wait_for_file_active(client: object, file_name: str, max_attempts: int = 30, delay: float = 1.0) -> bool:
    """
    Poll a file until it reaches ACTIVE state.
    
    Args:
        client: Gemini client instance
        file_name: Name of the uploaded file
        max_attempts: Maximum number of polling attempts
        delay: Delay between attempts in seconds
        
    Returns:
        True if file became active, False if timeout
    """
    for attempt in range(max_attempts):
        try:
            file_info = client.files.get(name=file_name)
            state = file_info.state
            print(f"File {file_name} state: {state} (attempt {attempt + 1}/{max_attempts})")
            
            if state == "ACTIVE":
                print(f"File {file_name} is now ACTIVE")
                return True
            elif state == "PROCESSING":
                print(f"File {file_name} is still processing, waiting...")
            else:
                print(f"File {file_name} in unexpected state: {state}")
            
            if attempt < max_attempts - 1:
                await __import__('asyncio').sleep(delay)
        except Exception as e:
            print(f"Error checking file status: {e}")
            if attempt < max_attempts - 1:
                await __import__('asyncio').sleep(delay)
    
    print(f"Timeout waiting for file {file_name} to become ACTIVE after {max_attempts} attempts")
    return False


async def transcribe_audio_gemini(file_path: str) -> str:
    """
    Transcribe audio file using Gemini API with structured output.
    
    Supports multiple formats: webm, mp3, aac, wav, ogg, flac
    Returns structured JSON with speaker diarization, timestamps, language detection,
    emotion analysis, and summary.
    
    Args:
        file_path: Path to audio file (local or S3 URI)
        
    Returns:
        JSON string with structured transcription data or empty string on failure
    """
    if not file_path:
        return ""
    
    if not _GENAI_AVAILABLE:
        print("google-genai package not available. Install with: pip install google-genai")
        use_placeholder = os.getenv("STT_FALLBACK_PLACEHOLDER", "true").lower() in {
            "1",
            "true",
            "yes",
        }
        return json.dumps({"summary": _placeholder_transcript(), "segments": []}) if use_placeholder else ""
    
    # Initialize client
    client = _get_gemini_client()
    if client is None:
        print("Failed to initialize Gemini client. Check GEMINI_API_KEY in settings.")
        use_placeholder = os.getenv("STT_FALLBACK_PLACEHOLDER", "true").lower() in {
            "1",
            "true",
            "yes",
        }
        return json.dumps({"summary": _placeholder_transcript(), "segments": []}) if use_placeholder else ""
    
    try:
        # Handle S3 URIs - download if needed
        local_file_path = file_path
        if file_path.startswith("s3://"):
            # For S3 files, assume they're already downloaded by worker
            # This function expects local paths
            print(f"Warning: S3 URI provided to transcribe_audio_gemini: {file_path}")
            print("Expected local file path. Transcription may fail.")
        
        # Verify file exists
        if not os.path.exists(local_file_path):
            print(f"Audio file not found: {local_file_path}")
            return ""
        
        # Get file size for logging
        file_size = os.path.getsize(local_file_path)
        print(f"Uploading audio file to Gemini: {local_file_path} ({file_size} bytes)")
        
        # Upload file to Gemini File API
        upload_start = time.time()
        uploaded_file = client.files.upload(file=local_file_path)
        upload_duration = time.time() - upload_start
        print(f"File uploaded to Gemini in {upload_duration:.2f}s: {uploaded_file.name}")
        
        # Wait for file to reach ACTIVE state
        print(f"Waiting for file {uploaded_file.name} to become ACTIVE...")
        file_active = await _wait_for_file_active(client, uploaded_file.name, max_attempts=60, delay=0.5)
        
        if not file_active:
            print(f"Error: File {uploaded_file.name} failed to reach ACTIVE state within timeout")
            try:
                client.files.delete(name=uploaded_file.name)
            except Exception:
                pass
            return ""
        
        # Get configured model
        model = _get_transcription_model()
        
        # Structured prompt for detailed transcription
        prompt = """
Process the audio file and generate a detailed transcription.

Requirements:
1. Identify distinct speakers (e.g., Speaker 1, Speaker 2, or names if context allows).
2. Provide accurate timestamps for each segment (Format: MM:SS or HH:MM:SS).
3. Detect the primary language of each segment.
4. Transcribe accurately using Latin/English characters. If the audio is in Hindi, Urdu, or other non-English languages, use Hinglish for transcription.
5. If the segment is in a language different than English, also provide the English translation.
6. Identify the primary emotion of the speaker in this segment. You MUST choose exactly one of the following: happy, sad, angry, neutral.
7. Provide a brief summary of the entire audio at the beginning.
        """
        
        # Request structured transcription
        print(f"Requesting structured transcription with model: {model}")
        transcribe_start = time.time()
        
        response = client.models.generate_content(
            model=model,
            contents=[
                types.Content(
                    parts=[
                        types.Part(file_data=types.FileData(file_uri=uploaded_file.uri)),
                        types.Part(text=prompt)
                    ]
                )
            ],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=types.Schema(
                    type=types.Type.OBJECT,
                    properties={
                        "summary": types.Schema(
                            type=types.Type.STRING,
                            description="A concise summary of the audio content.",
                        ),
                        "segments": types.Schema(
                            type=types.Type.ARRAY,
                            description="List of transcribed segments with speaker and timestamp.",
                            items=types.Schema(
                                type=types.Type.OBJECT,
                                properties={
                                    "speaker": types.Schema(type=types.Type.STRING),
                                    "timestamp": types.Schema(type=types.Type.STRING),
                                    "content": types.Schema(type=types.Type.STRING),
                                    "language": types.Schema(type=types.Type.STRING),
                                    "language_code": types.Schema(type=types.Type.STRING),
                                    "translation": types.Schema(type=types.Type.STRING),
                                    "emotion": types.Schema(
                                        type=types.Type.STRING,
                                        enum=["happy", "sad", "angry", "neutral"]
                                    ),
                                },
                                required=["speaker", "timestamp", "content", "language", "language_code", "emotion"],
                            ),
                        ),
                    },
                    required=["summary", "segments"],
                ),
            ),
        )
        
        transcribe_duration = time.time() - transcribe_start
        print(f"Structured transcription completed in {transcribe_duration:.2f}s")
        
        # Extract structured data from response
        transcript = response.text.strip() if response.text else ""
        
        # Clean up: Delete uploaded file from Gemini
        try:
            client.files.delete(name=uploaded_file.name)
            print(f"Cleaned up uploaded file: {uploaded_file.name}")
        except Exception as cleanup_error:
            print(f"Warning: Failed to delete uploaded file {uploaded_file.name}: {cleanup_error}")
        
        if not transcript:
            print("Warning: Empty transcript received from Gemini")
            return ""
        
        # Validate JSON structure
        try:
            data = json.loads(transcript)
            segments_count = len(data.get("segments", []))
            print(f"Transcription returned {segments_count} segments")
            print(f"Summary: {data.get('summary', 'N/A')[:100]}...")
        except json.JSONDecodeError:
            print("Warning: Response is not valid JSON")
        
        return transcript
        
    except Exception as e:
        print(f"Error during Gemini transcription: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()
        
        # Fallback behavior
        use_placeholder = os.getenv("STT_FALLBACK_PLACEHOLDER", "true").lower() in {
            "1",
            "true",
            "yes",
        }
        return json.dumps({"summary": _placeholder_transcript(), "segments": []}) if use_placeholder else ""


# Alias for consistency with existing code
transcribe_audio = transcribe_audio_gemini
