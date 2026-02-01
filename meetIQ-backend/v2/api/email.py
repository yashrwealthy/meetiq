from fastapi import APIRouter, Request, HTTPException
from pydantic import BaseModel
from typing import Optional, List
from arq.connections import ArqRedis
import json
import os
import logging

from settings import Settings
from ..services.storage import StorageService
from ..models.schemas import MeetingInsight
from ..agents.email_draft_agent import EmailDraftAgent

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v2/email", tags=["v2 email"])


class EmailDraftRequest(BaseModel):
    job_id: str
    client_name: Optional[str] = None
    partner_name: Optional[str] = None


class EmailDraftResponse(BaseModel):
    job_id: str
    status: str  # success, error, queued, processing, failed
    subject: Optional[str] = None
    body: Optional[str] = None
    suggested_attachments: List[str] = []
    tone: Optional[str] = None
    error: Optional[str] = None


@router.post("/draft", response_model=EmailDraftResponse)
async def generate_email_draft(
    request: Request,
    payload: EmailDraftRequest
) -> EmailDraftResponse:
    """
    Generate an email draft based on meeting analysis results.
    
    Takes a job_id, fetches the meeting result from Redis,
    and uses the EmailDraftAgent to create a professional email draft.
    """
    try:
        redis: ArqRedis = request.app.state.redis_pool
        settings = Settings()
        job_id = payload.job_id
        
        # Parse job_id format: v2-merge-{client_id}-{meeting_id}
        if not job_id.startswith("v2-merge-"):
            raise HTTPException(status_code=400, detail="Invalid job_id format. Expected: v2-merge-{client_id}-{meeting_id}")
        
        # Use rsplit to handle client_id containing hyphens (UUID)
        parts = job_id.replace("v2-merge-", "").rsplit("-", 1)
        if len(parts) != 2:
            raise HTTPException(status_code=400, detail="Invalid job_id format. Expected: v2-merge-{client_id}-{meeting_id}")
        
        client_id, meeting_id = parts
        
        # Check for result in Redis
        result_key = f"v2:meeting:{client_id}:{meeting_id}:result"
        result_bytes = await redis.get(result_key)
        
        if not result_bytes:
            # Check for error
            error_key = f"v2:meeting:{client_id}:{meeting_id}:error"
            error_bytes = await redis.get(error_key)
            if error_bytes:
                error_msg = error_bytes.decode('utf-8') if isinstance(error_bytes, bytes) else error_bytes
                return EmailDraftResponse(
                    job_id=job_id,
                    status="failed",
                    error=f"Meeting processing failed: {error_msg}"
                )
            
            # Check if processing has started
            processed_key = f"v2:meeting:{client_id}:{meeting_id}:processed"
            processed_bytes = await redis.get(processed_key)
            if processed_bytes:
                return EmailDraftResponse(
                    job_id=job_id,
                    status="processing",
                    error="Meeting is still being processed"
                )
            
            # Default: queued or not found
            return EmailDraftResponse(
                job_id=job_id,
                status="queued",
                error="Meeting not yet processed"
            )
        
        # Parse meeting insight from Redis
        result_str = result_bytes.decode('utf-8') if isinstance(result_bytes, bytes) else result_bytes
        meeting_insight = MeetingInsight.model_validate_json(result_str)
        
        # Load transcript (optional, for additional context)
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
        except Exception as e:
            logger.debug(f"Could not load transcript for email draft: {e}")
            transcript = None
        
        # Initialize EmailDraftAgent and generate draft
        email_agent = EmailDraftAgent(
            api_key=settings.gemini_api_key,
            model_name="gemini-2.5-flash"
        )
        
        email_draft = await email_agent.generate_draft(
            meeting_insight=meeting_insight,
            client_name=payload.client_name,
            partner_name=payload.partner_name,
            transcript=transcript
        )
        
        return EmailDraftResponse(
            job_id=job_id,
            status="success",
            subject=email_draft.subject,
            body=email_draft.body,
            suggested_attachments=email_draft.suggested_attachments,
            tone=email_draft.tone,
            error=None
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Error generating email draft: {e}")
        raise HTTPException(status_code=500, detail=str(e))
