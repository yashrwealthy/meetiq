from fastapi import APIRouter, File, Form, UploadFile, Request, HTTPException, Query, BackgroundTasks
from arq.connections import ArqRedis
from typing import Optional
import json
import os

from ..services.storage import StorageService
from ..models.schemas import MeetingEvent, MeetingInsight, ClientMemory # Just for ref check if needed, mostly for structure

# Reuse response models if compatible or create new ones
from pydantic import BaseModel

class ChunkUploadResponseV2(BaseModel):
    client_id: str
    meeting_id: str
    chunk_id: int
    status: str
    job_id: Optional[str] = None

class JobStatusResponseV2(BaseModel):
    job_id: str
    status: str  # queued, processing, complete, failed
    result: Optional[MeetingInsight] = None
    transcript: Optional[str] = None
    error: Optional[str] = None

class UploadAckResponseV2(BaseModel):
    client_id: str
    meeting_id: str
    total_chunks: int
    received_chunks_count: int
    status: str
    job_id: Optional[str] = None

router = APIRouter(prefix="/v2/meetings", tags=["meetings-v2"])

from services.audio_service import save_chunk_to_disk, process_chunk_background

@router.post("/upload_chunk", response_model=ChunkUploadResponseV2)
async def upload_chunk_v2(
    request: Request,
    background_tasks: BackgroundTasks,
    client_id: str = Form(...),
    meeting_id: str = Form(...),
    chunk_id: int = Form(...),
    total_chunks: int = Form(...),
    file: UploadFile = File(...)
) -> ChunkUploadResponseV2:
    try:
        # Save file to disk instantaneously
        file_path = await save_chunk_to_disk(file, client_id, meeting_id, chunk_id)
        
        redis: ArqRedis = request.app.state.redis_pool
        
        # Offload processing (convert -> S3 -> Redis update -> Trigger)
        background_tasks.add_task(
            process_chunk_background,
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

        return ChunkUploadResponseV2(
            client_id=client_id,
            meeting_id=meeting_id,
            chunk_id=chunk_id,
            status=f"uploading_background",
            job_id=job_id
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/ack", response_model=UploadAckResponseV2)
async def ack_upload_v2(
    request: Request,
    client_id: str = Query(...),
    meeting_id: str = Query(...),
    total_chunks: int = Query(...)
) -> UploadAckResponseV2:
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
        
        return UploadAckResponseV2(
            client_id=client_id,
            meeting_id=meeting_id,
            total_chunks=total_chunks,
            received_chunks_count=count,
            status=status,
            job_id=job_id
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/status", response_model=JobStatusResponseV2)
async def get_job_status_v2(
    request: Request,
    job_id: str = Query(...)
) -> JobStatusResponseV2:
    try:
        redis: ArqRedis = request.app.state.redis_pool
        
        # Extract client_id and meeting_id from job_id pattern: v2-merge-{client_id}-{meeting_id}
        if job_id.startswith("v2-merge-"):
            parts = job_id.replace("v2-merge-", "").split("-", 1)
            if len(parts) == 2:
                client_id, meeting_id = parts
                
                # Check for result
                result_key = f"v2:meeting:{client_id}:{meeting_id}:result"
                result_bytes = await redis.get(result_key)
                
                if result_bytes:
                    result_str = result_bytes.decode('utf-8') if isinstance(result_bytes, bytes) else result_bytes
                    result_data = MeetingInsight.model_validate_json(result_str)
                    
                    transcript = None
                    try:
                        storage = StorageService()
                        if storage.use_s3:
                            key = f"uploads/{client_id}/{meeting_id}/raw_event.json"
                            event_data = storage._s3_download_json(key)
                        else:
                            path = storage._get_meeting_dir(client_id, meeting_id)
                            file_path = os.path.join(path, "raw_event.json")
                            with open(file_path, 'r') as f:
                                event_data = json.load(f)
                        
                        transcript = event_data.get('transcript', '')
                    except Exception:
                        # Gracefully handle transcript fetch failure
                        transcript = None
                    
                    return JobStatusResponseV2(
                        job_id=job_id,
                        status="complete",
                        result=result_data,
                        transcript=transcript,
                        error=None
                    )
                
                # Check for error
                error_key = f"v2:meeting:{client_id}:{meeting_id}:error"
                error_bytes = await redis.get(error_key)
                if error_bytes:
                    error_msg = error_bytes.decode('utf-8') if isinstance(error_bytes, bytes) else error_bytes
                    return JobStatusResponseV2(
                        job_id=job_id,
                        status="failed",
                        result=None,
                        transcript=None,
                        error=error_msg
                    )
                
                # Check if processing has started
                processed_key = f"v2:meeting:{client_id}:{meeting_id}:processed"
                processed_bytes = await redis.get(processed_key)
                if processed_bytes:
                    return JobStatusResponseV2(
                        job_id=job_id,
                        status="processing",
                        result=None,
                        transcript=None,
                        error=None
                    )
        
        # Default: queued or not found
        return JobStatusResponseV2(
            job_id=job_id,
            status="queued",
            result=None,
            transcript=None,
            error=None
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@router.get("/memory", response_model=ClientMemory)
async def get_client_memory_v2(
    client_id: str = Query(...)
) -> ClientMemory:
    try:
        storage = StorageService()
        memory = storage.load_client_memory(client_id)
        return memory
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
