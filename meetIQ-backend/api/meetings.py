from fastapi import APIRouter, File, Form, UploadFile

from agents.meeting_agent import MeetingAgent
from models.schemas import MeetingOutput
from services.audio_service import save_upload_file
from services.stt_service import transcribe_audio
from utils.cleanup import cleanup_file

router = APIRouter()


@router.post("/process", response_model=MeetingOutput)
async def process_meeting(
    meeting_id: str = Form(...),
    audio_file: UploadFile = File(...),
) -> MeetingOutput:
    file_path = ""
    try:
        file_path = await save_upload_file(audio_file, meeting_id)
        transcript = await transcribe_audio(file_path)
        if not transcript or not transcript.strip():
            return MeetingOutput(
                is_financial_meeting=False,
                financial_products=[],
                client_intent="",
                meeting_summary=[],
                action_items=[],
                follow_up_date=None,
                confidence_level="low",
            )
        agent = MeetingAgent()
        return await agent.run(transcript)
    except Exception:
        return MeetingOutput(
            is_financial_meeting=False,
            financial_products=[],
            client_intent="",
            meeting_summary=[],
            action_items=[],
            follow_up_date=None,
            confidence_level="low",
        )
    finally:
        cleanup_file(file_path)
