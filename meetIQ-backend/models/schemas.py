from typing import List, Optional, Literal

from pydantic import BaseModel


class MeetingOutput(BaseModel):
    is_financial_meeting: bool
    financial_products: List[str]
    client_intent: str
    meeting_summary: List[str]
    action_items: List[str]
    follow_up_date: Optional[str]
    confidence_level: Literal["high", "medium", "low"]
    transcript: Optional[str] = None

class JobSubmission(BaseModel):
    job_id: str
    status: str


class JobStatus(BaseModel):
    job_id: str
    status: str
    result: Optional[MeetingOutput] = None
    error: Optional[str] = None


class ChunkUploadResponse(BaseModel):
    client_id: str
    meeting_id: str
    chunk_id: int
    status: str
    job_id: Optional[str] = None


class UploadAckResponse(BaseModel):
    client_id: str
    meeting_id: str
    total_chunks: int
    received_chunks_count: int
    missing_chunks: List[int]
    status: Literal["complete", "incomplete"]


