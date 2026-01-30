"""
V2 Meetings API with Gemini Transcription
Uses audio_service_v2 (no format conversion) and worker_gemini for processing.
"""
from fastapi import APIRouter, File, Form, UploadFile, Request, HTTPException, Query, BackgroundTasks
from arq.connections import ArqRedis
from typing import Optional
import json
import os

from v2.services.storage import StorageService
from v2.models.schemas import MeetingEvent, MeetingInsight, ClientMemory

from pydantic import BaseModel

class ChunkUploadResponseV2Gemini(BaseModel):
    client_id: str
    meeting_id: str
    chunk_id: int
    status: str
    job_id: Optional[str] = None
    transcription_engine: str = "gemini"

class JobStatusResponseV2Gemini(BaseModel):
    job_id: str
    status: str  # queued, processing, complete, failed
    result: Optional[MeetingInsight] = None
    transcript: Optional[str] = None
    error: Optional[str] = None
    transcription_engine: str = "gemini"

class UploadAckResponseV2Gemini(BaseModel):
    client_id: str
    meeting_id: str
    total_chunks: int
    received_chunks_count: int
    status: str
    job_id: Optional[str] = None
    transcription_engine: str = "gemini"

router = APIRouter(prefix="/v2/meetings/gemini", tags=["meetings-v2-gemini"])

from services.audio_service_v2 import save_chunk_to_disk, process_chunk_background_v2

@router.post("/upload_chunk", response_model=ChunkUploadResponseV2Gemini)
async def upload_chunk_v2_gemini(
    request: Request,
    background_tasks: BackgroundTasks,
    client_id: str = Form(...),
    meeting_id: str = Form(...),
    chunk_id: int = Form(...),
    total_chunks: int = Form(...),
    file: UploadFile = File(...)
) -> ChunkUploadResponseV2Gemini:
    """
    Upload audio chunk for Gemini transcription.
    Supports webm, mp3, aac, wav without format conversion.
    """
    try:
        # Save file to disk (preserves original format)
        file_path = await save_chunk_to_disk(file, client_id, meeting_id, chunk_id)
        
        redis: ArqRedis = request.app.state.redis_pool
        
        # Offload processing (S3 upload -> Redis update -> Trigger Gemini pipeline)
        background_tasks.add_task(
            process_chunk_background_v2,
            file_path,
            client_id,
            meeting_id,
            chunk_id,
            total_chunks,
            redis
        )

        # Check if job_id already exists (from previous chunks)
        job_key = f"v2:meeting:{client_id}:{meeting_id}:job_id"
        job_id_bytes = await redis.get(job_key)
        job_id = None
        if job_id_bytes:
            job_id = job_id_bytes.decode('utf-8') if isinstance(job_id_bytes, bytes) else job_id_bytes

        return ChunkUploadResponseV2Gemini(
            client_id=client_id,
            meeting_id=meeting_id,
            chunk_id=chunk_id,
            status=f"uploading_background",
            job_id=job_id,
            transcription_engine="gemini"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/ack", response_model=UploadAckResponseV2Gemini)
async def ack_upload_v2_gemini(
    request: Request,
    client_id: str = Query(...),
    meeting_id: str = Query(...),
    total_chunks: int = Query(...)
) -> UploadAckResponseV2Gemini:
    """
    Acknowledge upload status for Gemini transcription pipeline.
    """
    try:
        redis: ArqRedis = request.app.state.redis_pool
        key = f"v2:meeting:{client_id}:{meeting_id}:uploaded"
        uploaded_chunks = await redis.smembers(key)
        uploaded_ids = {int(x) for x in uploaded_chunks}
        
        count = len(uploaded_ids)
        status = "complete" if count == total_chunks else "incomplete"
        
        job_id = None
        if status == "complete":
            job_key = f"v2:meeting:{client_id}:{meeting_id}:job_id"
            job_id_bytes = await redis.get(job_key)
            if job_id_bytes:
                job_id = job_id_bytes.decode('utf-8') if isinstance(job_id_bytes, bytes) else job_id_bytes
        
        return UploadAckResponseV2Gemini(
            client_id=client_id,
            meeting_id=meeting_id,
            total_chunks=total_chunks,
            received_chunks_count=count,
            status=status,
            job_id=job_id,
            transcription_engine="gemini"
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/status/{client_id}/{meeting_id}", response_model=JobStatusResponseV2Gemini)
async def get_status_v2_gemini(
    request: Request,
    client_id: str,
    meeting_id: str
) -> JobStatusResponseV2Gemini:
    """
    Get processing status for a meeting using Gemini transcription.
    """
    try:
        redis: ArqRedis = request.app.state.redis_pool
        
        # Get job_id
        job_key = f"v2:meeting:{client_id}:{meeting_id}:job_id"
        job_id_bytes = await redis.get(job_key)
        if not job_id_bytes:
            raise HTTPException(status_code=404, detail="Meeting not found or not yet started")
        
        job_id = job_id_bytes.decode('utf-8') if isinstance(job_id_bytes, bytes) else job_id_bytes
        
        # Check for errors first
        error_key = f"v2:meeting:{client_id}:{meeting_id}:error"
        error_bytes = await redis.get(error_key)
        if error_bytes:
            error_msg = error_bytes.decode('utf-8') if isinstance(error_bytes, bytes) else error_bytes
            return JobStatusResponseV2Gemini(
                job_id=job_id,
                status="failed",
                error=error_msg,
                transcription_engine="gemini"
            )
        
        # Check for result
        result_key = f"v2:meeting:{client_id}:{meeting_id}:result"
        result_bytes = await redis.get(result_key)
        
        if result_bytes:
            # Complete
            result_json = result_bytes.decode('utf-8') if isinstance(result_bytes, bytes) else result_bytes
            insight = MeetingInsight.model_validate_json(result_json)
            
            # Load transcript if needed
            storage = StorageService()
            transcript = None
            try:
                if storage.use_s3:
                    txt_key = f"uploads/{client_id}/{meeting_id}/full_transcript.txt"
                    resp = storage.s3_client.get_object(Bucket=storage.bucket_name, Key=txt_key)
                    transcript = resp['Body'].read().decode('utf-8')
                else:
                    from pathlib import Path
                    txt_path = Path("uploads") / client_id / meeting_id / "full_transcript.txt"
                    if txt_path.exists():
                        with open(txt_path, 'r') as f:
                            transcript = f.read()
            except Exception as e:
                print(f"Could not load transcript: {e}")
            
            return JobStatusResponseV2Gemini(
                job_id=job_id,
                status="complete",
                result=insight,
                transcript=transcript,
                transcription_engine="gemini"
            )
        
        # Check progress
        processed_key = f"v2:meeting:{client_id}:{meeting_id}:processed"
        processed_bytes = await redis.get(processed_key)
        uploaded_key = f"v2:meeting:{client_id}:{meeting_id}:uploaded"
        uploaded_chunks = await redis.smembers(uploaded_key)
        total = len(uploaded_chunks)
        
        if processed_bytes:
            processed = int(processed_bytes)
            if processed < total:
                return JobStatusResponseV2Gemini(
                    job_id=job_id,
                    status=f"processing ({processed}/{total} chunks)",
                    transcription_engine="gemini"
                )
        
        # Default to queued
        return JobStatusResponseV2Gemini(
            job_id=job_id,
            status="queued",
            transcription_engine="gemini"
        )
        
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/memory/{client_id}")
async def get_client_memory_gemini(client_id: str):
    """
    Retrieve client memory generated from Gemini-transcribed meetings.
    """
    try:
        storage = StorageService()
        memory = storage.load_client_memory(client_id)
        return memory.model_dump()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/insight/{client_id}/{meeting_id}")
async def get_meeting_insight_gemini(client_id: str, meeting_id: str):
    """
    Retrieve meeting insight for a specific meeting (Gemini transcription).
    """
    try:
        storage = StorageService()
        insight = storage.load_meeting_insight(client_id, meeting_id)
        if not insight:
            raise HTTPException(status_code=404, detail="Insight not found")
        return insight.model_dump()
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
