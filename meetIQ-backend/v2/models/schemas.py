from pydantic import BaseModel, Field
from typing import List, Dict, Optional, Literal
from datetime import datetime

# Layer 1: Raw Event Store (Immutable, append-only)
class MeetingEvent(BaseModel):
    meeting_id: str
    client_id: str
    timestamp: datetime
    audio_chunks_ref: List[str]
    transcript: str
    speaker_map: Dict[str, str] = Field(default_factory=dict, description="Map of speaker_id to role (advisor/client)")

# Layer 2: Meeting Intelligence (Per-meeting outputs)
class MeetingInsight(BaseModel):
    meeting_id: str
    is_financial_meeting: bool
    financial_products: List[str]
    client_intent: str
    meeting_summary: List[str]
    action_items: List[str]
    follow_ups: List[str]
    follow_up_date: Optional[str]
    confidence_level: Literal["high", "medium", "low"]

class FinancialGoal(BaseModel):
    name: str
    status: str

# Layer 3: Client Memory State (Long-term evolving memory)
class ClientMemory(BaseModel):
    client_id: str

    # Stable identity & preferences
    profile: Dict[str, str] = Field(default_factory=dict, description="Basic client details like age, occupation, etc.")
    risk_profile: Optional[str] = None
    preferred_products: List[str] = Field(default_factory=list)
    disfavored_products: List[str] = Field(default_factory=list)

    # Financial trajectory (derived over time)
    active_financial_goals: List[FinancialGoal] = Field(default_factory=list)
    discussed_products: Dict[str, int] = Field(default_factory=dict)  # product -> times discussed
    objections_history: List[str] = Field(default_factory=list)

    # Behavioral signals
    decision_confidence_trend: Literal["increasing", "stable", "decreasing"] = "stable"
    engagement_level: Literal["high", "medium", "low"] = "medium"

    # Commitments & follow-ups
    pending_action_items: List[str] = Field(default_factory=list)
    last_follow_up_date: Optional[str] = None

    # Memory hygiene
    last_updated_from_meeting_id: Optional[str] = None
    memory_confidence: Literal["high", "medium", "low"] = "medium"
