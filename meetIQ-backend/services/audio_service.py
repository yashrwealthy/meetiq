import os
import subprocess
import tempfile
from pathlib import Path
from typing import Optional

from fastapi import UploadFile


async def save_upload_file(upload_file: UploadFile, meeting_id: Optional[str] = None) -> str:
    temp_dir = tempfile.mkdtemp(prefix="meetiq_")
    original_name = upload_file.filename or "audio"
    ext = Path(original_name).suffix or ".wav"
    safe_meeting_id = (meeting_id or "meeting").replace("/", "-")
    file_path = Path(temp_dir) / f"{safe_meeting_id}{ext}"

    content = await upload_file.read()
    with open(file_path, "wb") as f:
        f.write(content)

    await upload_file.close()
    return os.fspath(file_path)


async def save_chunk_file(
    upload_file: UploadFile,
    client_id: str,
    meeting_id: str,
    chunk_id: int
) -> str:
    base_dir = Path("uploads") / client_id / meeting_id
    base_dir.mkdir(parents=True, exist_ok=True)
    
    # Determine extension from filename or use default
    filename = upload_file.filename or ""
    ext = Path(filename).suffix
    if not ext:
        # Fallback to content-type if filename has no extension
        if upload_file.content_type == "audio/webm":
            ext = ".webm"
        else:
            ext = ".aac"
            
    file_path = base_dir / f"chunk_{chunk_id}{ext}"
    
    content = await upload_file.read()
    with open(file_path, "wb") as f:
        f.write(content)
        
    await upload_file.close()

    if ext == ".webm":
        new_file_path = file_path.with_suffix(".aac")
        try:
            subprocess.run(
                ["ffmpeg", "-y", "-i", str(file_path), "-vn", "-c:a", "aac", str(new_file_path)],
                check=True,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL
            )
            os.remove(file_path)
            return os.fspath(new_file_path)
        except (subprocess.SubprocessError, FileNotFoundError):
            return os.fspath(file_path)

    return os.fspath(file_path)

