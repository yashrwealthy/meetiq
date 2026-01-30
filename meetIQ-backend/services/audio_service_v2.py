"""
Audio Service V2 - Optimized for Gemini Transcription
Removes unnecessary format conversions since Gemini natively supports webm, mp3, aac, wav, etc.
"""
import os
import boto3
import asyncio
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from typing import Optional

from fastapi import UploadFile

try:
    from settings import Settings
except ImportError:
    import sys
    sys.path.append(os.getcwd())
    from settings import Settings

# Create a thread pool for blocking S3 operations
_s3_executor = ThreadPoolExecutor(max_workers=5)
# Cache settings
_settings_cache = None


def _get_settings():
    global _settings_cache
    if _settings_cache is None:
        _settings_cache = Settings()
    return _settings_cache


def _upload_to_s3_sync(file_path: str, bucket: str, key: str, region: str, awk: str, sak: str):
    """Synchronous S3 upload for use in thread pool."""
    s3 = boto3.client(
        's3',
        region_name=region,
        aws_access_key_id=awk,
        aws_secret_access_key=sak
    )
    s3.upload_file(file_path, bucket, key)


async def save_chunk_to_disk(
    upload_file: UploadFile,
    client_id: str,
    meeting_id: str,
    chunk_id: int
) -> str:
    """
    Save uploaded audio chunk to disk.
    Preserves original format (no conversion needed for Gemini).
    """
    base_dir = Path("uploads") / client_id / meeting_id
    base_dir.mkdir(parents=True, exist_ok=True)
    
    filename = upload_file.filename or ""
    ext = Path(filename).suffix
    if not ext:
        # Default to webm if no extension provided
        if upload_file.content_type == "audio/webm":
            ext = ".webm"
        elif upload_file.content_type == "audio/mpeg":
            ext = ".mp3"
        else:
            ext = ".webm"  # Default to webm since Gemini supports it
            
    file_path = base_dir / f"chunk_{chunk_id}{ext}"
    
    content = await upload_file.read()
    with open(file_path, "wb") as f:
        f.write(content)
        
    await upload_file.close()
    return os.fspath(file_path)


async def handle_s3_upload(file_path_str: str, client_id: str, meeting_id: str) -> str:
    """
    Upload audio file to S3 without format conversion.
    
    Args:
        file_path_str: Path to the audio file
        client_id: Client identifier
        meeting_id: Meeting identifier
        
    Returns:
        S3 URI if uploaded successfully, otherwise local file path
    """
    file_path = Path(file_path_str)
    
    # S3 Integration (no conversion needed)
    try:
        settings = _get_settings()
        if settings.bucket_name and settings.s3_access_key and settings.s3_secret_key:
            # Use same structure: uploads/client_id/meeting_id/filename
            key = f"uploads/{client_id}/{meeting_id}/{os.path.basename(file_path)}"
            
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(
                _s3_executor,
                _upload_to_s3_sync,
                str(file_path),
                settings.bucket_name,
                key,
                settings.s3_region,
                settings.s3_access_key,
                settings.s3_secret_key
            )
            
            # Delete local file after successful upload
            os.remove(file_path)
            
            # Return S3 URI
            return f"s3://{settings.bucket_name}/{key}"
    except Exception as e:
        print(f"S3 Upload failed: {e}")
        # Return local path if S3 fails
        return os.fspath(file_path)
    
    return os.fspath(file_path)


async def process_chunk_background_v2(
    file_path_str: str,
    client_id: str,
    meeting_id: str,
    chunk_id: int,
    total_chunks: int,
    redis
):
    final_path_str = await handle_s3_upload(file_path_str, client_id, meeting_id)

    # Update Redis Logic
    uploaded_key = f"v2:meeting:{client_id}:{meeting_id}:uploaded"
    await redis.sadd(uploaded_key, chunk_id)
    
    # Check completeness
    uploaded_chunks = await redis.smembers(uploaded_key)
    uploaded_ids = {int(x) for x in uploaded_chunks}
    
    if len(uploaded_ids) == total_chunks:
        # All chunks uploaded - trigger V2 Pipeline
        print(f"All chunks uploaded for {meeting_id}. Dispatching V2 Gemini pipeline.")
        
        # Generate merge job_id upfront for status tracking
        merge_job_id = f"v2-merge-{client_id}-{meeting_id}"
        
        # Save job_id immediately so clients can start polling
        job_key = f"v2:meeting:{client_id}:{meeting_id}:job_id"
        await redis.set(job_key, merge_job_id)
        
        job = await redis.enqueue_job(
            'dispatch_processing_task_v2',
            client_id,
            meeting_id,
            total_chunks,
            _queue_name='arq:queue:v2'
        )
