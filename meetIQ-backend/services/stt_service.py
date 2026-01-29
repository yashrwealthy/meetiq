from __future__ import annotations

import os
import shutil
from typing import Optional


try:
    import whisper  # type: ignore

    _WHISPER_AVAILABLE = True
    _WHISPER_MODEL: Optional[object] = None
except Exception:
    whisper = None  # type: ignore
    _WHISPER_AVAILABLE = False
    _WHISPER_MODEL = None


def _get_whisper_model() -> Optional[object]:
    global _WHISPER_MODEL
    if not _WHISPER_AVAILABLE:
        return None
    if _WHISPER_MODEL is None and whisper is not None:
        _WHISPER_MODEL = whisper.load_model("base")
    return _WHISPER_MODEL


def _placeholder_transcript() -> str:
    return (
        "Placeholder transcript: The team reviewed current progress, discussed blockers, "
        "and agreed on next steps for the upcoming sprint."
    )


async def transcribe_audio(file_path: str) -> str:
    if not file_path:
        return ""

    if not _WHISPER_AVAILABLE:
        return _placeholder_transcript()

    if shutil.which("ffmpeg") is None:
        use_placeholder = os.getenv("STT_FALLBACK_PLACEHOLDER", "true").lower() in {
            "1",
            "true",
            "yes",
        }
        return _placeholder_transcript() if use_placeholder else ""

    try:
        model = _get_whisper_model()
        if model is None:
            return ""
        result = model.transcribe(file_path)
        text = (result or {}).get("text", "").strip()
        if text:
            return text
    except Exception:
        pass

    use_placeholder = os.getenv("STT_FALLBACK_PLACEHOLDER", "true").lower() in {
        "1",
        "true",
        "yes",
    }
    return _placeholder_transcript() if use_placeholder else ""
