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
