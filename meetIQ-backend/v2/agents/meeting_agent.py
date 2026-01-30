import json
import logging
from typing import Optional
from datetime import datetime
from google import genai
from google.genai import types
from ..models.schemas import MeetingInsight

logger = logging.getLogger(__name__)

class MeetingAgent:
    def __init__(self, api_key: Optional[str], model_name: str = "gemini-2.5-flash"):
        self.model_name = model_name
        if api_key:
            self.client = genai.Client(api_key=api_key)
        else:
            self.client = None
            logger.warning("Gemini API key missing; skipping meeting analysis.")

    def _empty_insight(self, meeting_id: str) -> MeetingInsight:
        return MeetingInsight(
            meeting_id=meeting_id,
            is_financial_meeting=False,
            financial_products=[],
            client_intent="",
            meeting_summary=[],
            action_items=[],
            follow_ups=[],
            follow_up_date=None,
            confidence_level="low"
        )

    async def analyze(self, transcript: str, meeting_id: str) -> MeetingInsight:
        logger.info(f"Analyzing meeting {meeting_id} for insights...")

        if not self.client or not transcript or not transcript.strip():
            return self._empty_insight(meeting_id)
        
        prompt = f"""
        You are an expert financial meeting analyst. Analyze the following meeting transcript and extract structured insights.
        
        Your output must strictly follow this JSON structure:
        {{
            "meeting_id": "{meeting_id}",
            "is_financial_meeting": boolean,
            "financial_products": [list of strings],
            "client_intent": string (summary of what the client wants),
            "meeting_summary": [list of key distinct points],
            "action_items": [list of specific tasks],
            "follow_ups": [list of follow-up topics],
            "follow_up_date": string (YYYY-MM-DD or null),
            "confidence_level": "high" | "medium" | "low"
        }}

        Transcript:
        {transcript}
        
        Return ONLY valid JSON.
        """

        try:
            response = self.client.models.generate_content(
                model=self.model_name,
                contents=prompt,
                config=types.GenerateContentConfig(response_mime_type="application/json")
            )
            
            data = json.loads(response.text)
            # key validation/mapping if necessary
            return MeetingInsight(**data)
            
        except Exception as e:
            logger.error(f"Error analyzing meeting: {e}")
            # Fallback or re-raise
            raise e
