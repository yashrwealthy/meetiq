import os
import subprocess
import tempfile
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

_s3_executor = ThreadPoolExecutor(max_workers=5)

_settings_cache = None

def _get_settings():
    global _settings_cache
    if _settings_cache is None:
        _settings_cache = Settings()
    return _settings_cache

def _upload_to_s3_sync(file_path: str, bucket: str, key: str, region: str, awk: str, sak: str):
    s3 = boto3.client(
        's3',
        region_name=region,
        aws_access_key_id=awk,
        aws_secret_access_key=sak
    )
    s3.upload_file(file_path, bucket, key)

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


async def save_chunk_to_disk(
    upload_file: UploadFile,
    client_id: str,
    meeting_id: str,
    chunk_id: int
) -> str:
    base_dir = Path("uploads") / client_id / meeting_id
    base_dir.mkdir(parents=True, exist_ok=True)
    
    filename = upload_file.filename or ""
    ext = Path(filename).suffix
    if not ext:
        if upload_file.content_type == "audio/webm":
            ext = ".webm"
        else:
            ext = ".aac"
            
    file_path = base_dir / f"chunk_{chunk_id}{ext}"
    
    content = await upload_file.read()
    with open(file_path, "wb") as f:
        f.write(content)
        
    await upload_file.close()
    return os.fspath(file_path)

async def _handle_conversion_and_s3(file_path_str: str, client_id: str, meeting_id: str) -> str:
    file_path = Path(file_path_str)
    final_path = file_path
    try:
        settings = _get_settings()
        if settings.bucket_name and settings.s3_access_key and settings.s3_secret_key:
            # Use same structure: uploads/client_id/meeting_id/filename
            key = f"uploads/{client_id}/{meeting_id}/{os.path.basename(final_path)}"
            
            loop = asyncio.get_running_loop()
            await loop.run_in_executor(
                _s3_executor,
                _upload_to_s3_sync,
                str(final_path),
                settings.bucket_name,
                key,
                settings.s3_region,
                settings.s3_access_key,
                settings.s3_secret_key
            )
            
            os.remove(final_path)
            # Return S3 URI
            return f"s3://{settings.bucket_name}/{key}"
    except Exception as e:
        print(f"S3 Upload failed: {e}")
        # Return local path if S3 fails
        return os.fspath(final_path)
    
    return os.fspath(final_path)

async def process_chunk_background(
    file_path_str: str,
    client_id: str,
    meeting_id: str,
    chunk_id: int,
    total_chunks: int,
    redis
):
    # Use helper
    final_path_str = await _handle_conversion_and_s3(file_path_str, client_id, meeting_id)

    # Update Redis Logic (Moved from API handler)
    uploaded_key = f"v2:meeting:{client_id}:{meeting_id}:uploaded"
    await redis.sadd(uploaded_key, chunk_id)
    
    # Check completeness
    uploaded_chunks = await redis.smembers(uploaded_key)
    uploaded_ids = {int(x) for x in uploaded_chunks}
    
    if len(uploaded_ids) == total_chunks:
        # Trigger V2 Pipeline
        print(f"All chunks uploaded for {meeting_id}. Dispatching V2 pipeline.")
        
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

async def save_chunk_file(
    upload_file: UploadFile,
    client_id: str,
    meeting_id: str,
    chunk_id: int
) -> str:
    # Save to disk first
    file_path = await save_chunk_to_disk(upload_file, client_id, meeting_id, chunk_id)
    
    # Now handle conversion and S3 upload synchronously to maintain V1 contract
    # This might block slightly longer but safeguards V1 compatibility
    final_path = await _handle_conversion_and_s3(file_path, client_id, meeting_id)
    
    return final_path

