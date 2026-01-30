from fastapi import APIRouter, File, Form, UploadFile, Request, HTTPException, Query
from arq.jobs import Job, JobStatus as ArqJobStatus
from arq.connections import ArqRedis

from models.schemas import MeetingOutput, JobSubmission, JobStatus, ChunkUploadResponse, UploadAckResponse
from services.audio_service import save_upload_file, save_chunk_file

router = APIRouter()


@router.post("/process", response_model=JobSubmission)
async def process_meeting(
    request: Request,
    meeting_id: str = Form(...),
    audio_file: UploadFile = File(...),
) -> JobSubmission:
    file_path = ""
    try:
        file_path = await save_upload_file(audio_file, meeting_id)
        
        redis: ArqRedis = request.app.state.redis_pool
        job = await redis.enqueue_job('process_meeting_task', file_path, meeting_id)
        
        if not job:
            raise HTTPException(status_code=500, detail="Failed to enqueue job")
            
        return JobSubmission(job_id=job.job_id, status="queued")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/status/{job_id}", response_model=JobStatus)
async def get_status(job_id: str, request: Request) -> JobStatus:
    redis: ArqRedis = request.app.state.redis_pool
    try:
        job = Job(job_id, redis)
        status = await job.status()
        
        result = None
        error = None
        response_status = str(status)
        
        if status == ArqJobStatus.complete:
            try:
                job_result = await job.result()
                
                # Handle dispatch task result
                if isinstance(job_result, dict) and job_result.get("status") == "dispatched":
                    # This is the intermediate dispatch result, not the final MeetingOutput
                    # So we default result to None and status to processing
                    result = None
                    response_status = "processing"
                    
                    try:
                        job_info = await job.info()
                        
                        if job_info and job_info.function == 'dispatch_processing_task':
                            client_id = job_info.args[0]
                            meeting_id = job_info.args[1]
                            
                            merge_job_id = f"merge-{client_id}-{meeting_id}"
                            merge_job = Job(merge_job_id, redis)
                            merge_status = await merge_job.status()
                            
                            if merge_status == ArqJobStatus.complete:
                                result = await merge_job.result()
                                response_status = "complete"
                            elif merge_status == ArqJobStatus.failed:
                                response_status = "failed"
                                try:
                                    await merge_job.result()
                                except Exception as e:
                                    error = str(e)
                    except Exception:
                        # If finding/checking merge job fails, we stick to processing/None
                        # or could set error. But for now, let's keep it safe.
                        pass
                else:
                    result = job_result

            except Exception as e:
                result = None
                error = str(e)
                response_status = "failed"
        
        return JobStatus(
            job_id=job_id,
            status=response_status,
            result=result,
            error=error
        )
    except Exception as e:
        return JobStatus(job_id=job_id, status="unknown", error=str(e))


@router.post("/upload_chunk", response_model=ChunkUploadResponse)
async def upload_chunk(
    request: Request,
    client_id: str = Form(...),
    meeting_id: str = Form(...),
    chunk_id: int = Form(...),
    total_chunks: int = Form(...),
    file: UploadFile = File(...)
) -> ChunkUploadResponse:
    try:
        file_path = await save_chunk_file(file, client_id, meeting_id, chunk_id)
        
        redis: ArqRedis = request.app.state.redis_pool
        
        uploaded_key = f"meeting:{client_id}:{meeting_id}:uploaded"
        await redis.sadd(uploaded_key, chunk_id)
        
        uploaded_chunks = await redis.smembers(uploaded_key)
        uploaded_ids = {int(x) for x in uploaded_chunks}
        
        if len(uploaded_ids) == total_chunks:
            # Check if we already started processing to avoid duplicates (optional but good practice)
            # For now, relying on the fact that the last chunk triggers this block
            
            # Enqueue the dispatch task
            job = await redis.enqueue_job(
                'dispatch_processing_task',
                client_id,
                meeting_id,
                total_chunks
            )

            job_key = f"meeting:{client_id}:{meeting_id}:job_id"
            await redis.set(job_key, job.job_id)
             
            return ChunkUploadResponse(
                client_id=client_id,
                meeting_id=meeting_id,
                chunk_id=chunk_id,
                status="processing_started",
                job_id=job.job_id
            )
            
        return ChunkUploadResponse(
            client_id=client_id,
            meeting_id=meeting_id,
            chunk_id=chunk_id,
            status="uploaded",
            job_id=None
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get("/ack_upload", response_model=UploadAckResponse)
async def ack_upload(
    request: Request,
    client_id: str = Query(...),
    meeting_id: str = Query(...),
    total_chunks: int = Query(...)
) -> UploadAckResponse:
    try:
        redis: ArqRedis = request.app.state.redis_pool
        key = f"meeting:{client_id}:{meeting_id}:uploaded"
        uploaded_chunks = await redis.smembers(key)
        uploaded_ids = {int(x) for x in uploaded_chunks}
        
        count = len(uploaded_ids)
        expected_ids = set(range(total_chunks))
        missing_ids = list(expected_ids - uploaded_ids)
        missing_ids.sort()
        
        status = "complete" if not missing_ids else "incomplete"

        job_id = None
        if status == "complete":
            job_key = f"meeting:{client_id}:{meeting_id}:job_id"
            job_id_bytes = await redis.get(job_key)
            if job_id_bytes:
                job_id = job_id_bytes.decode('utf-8') if isinstance(job_id_bytes, bytes) else job_id_bytes
        
        return UploadAckResponse(
            client_id=client_id,
            meeting_id=meeting_id,
            total_chunks=total_chunks,
            received_chunks_count=count,
            missing_chunks=missing_ids,
            status=status,
            job_id=job_id
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


