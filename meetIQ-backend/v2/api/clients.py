from fastapi import APIRouter, Request, HTTPException, Depends
from typing import Optional, List, Dict, Any
from pydantic import BaseModel
import logging
import json

from settings import Settings
from ..services.storage import StorageService
from ..services.toolbox_service import ToolboxService, get_toolbox_service
from ..agents.client_overview_agent import ClientOverviewAgent
from ..models.schemas import ClientMemory, MeetingInsight, ClientAdvisorReport

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/v2/clients", tags=["v2 clients"])

class ClientOverviewResponse(ClientAdvisorReport):
    client_id: str
    last_meeting_date: Optional[str] = None

def get_dummy_insight() -> MeetingInsight:
    return MeetingInsight(
        meeting_id="no-meeting",
        is_financial_meeting=False,
        financial_products=[],
        client_intent="No prior meetings recorded",
        meeting_summary=[],
        action_items=[],
        follow_ups=[],
        follow_up_date=None,
        confidence_level="low"
    )

@router.get("/{client_id}/overview", response_model=ClientOverviewResponse)
async def get_client_overview(
    request: Request,
    client_id: str
) -> ClientOverviewResponse:
    client_id = client_id.replace("-", "")
    try:
        # Check cache first
        redis_pool = getattr(request.app.state, "redis_pool", None)
        cache_key = f"v2:client_overview:{client_id}"
        
        if redis_pool:
            cached_bytes = await redis_pool.get(cache_key)
            if cached_bytes:
                cached_data = json.loads(cached_bytes)
                logger.info(f"Returning cached overview for {client_id}")
                return ClientOverviewResponse(**cached_data)

        settings = Settings()
        storage = StorageService()
        
        # Initialize Toolbox Service (Singleton)
        toolbox = get_toolbox_service(
            toolbox_url=settings.toolbox_url,
            redis_client=redis_pool,
            cache_ttl=settings.toolbox_cache_ttl
        )
        
        # Initialize Agent
        agent = ClientOverviewAgent(
            api_key=settings.gemini_api_key,
            model_name="gemini-2.5-flash",
            toolbox_service=toolbox
        )

        # 1. Load Memory
        memory = storage.load_client_memory(client_id)
        if not memory:
             # Create default memory if none exists
             memory = ClientMemory(client_id=client_id)

        # 2. Load most recent meeting insight
        meeting_ids = storage.list_meeting_ids(client_id)
        recent_insight = None
        last_meeting_date = None
        
        if meeting_ids:
            recent_mid = sorted(meeting_ids, reverse=True)[0]
            recent_insight = storage.load_meeting_insight(client_id, recent_mid)
            if recent_insight and hasattr(recent_insight, 'timestamp'):
                 # MeetingInsight doesn't have timestamp directly on it? 
                 # Wait, meeting_event does. meeting_insight relies on storage usually not having ts directly, 
                 # but let's check schema.
                 # Schema says `MeetingInsight` has `meeting_id`. `MeetingEvent` has `timestamp`.
                 # Meeting ID might contain TS or not.
                 # Let's leave last_meeting_date as None if not easily available or derive from meeting_id if possible.
                 pass
        
        if not recent_insight:
             recent_insight = get_dummy_insight()
        
        # 4. Generate Report
        report = await agent.generate_advisor_report(
            client_id=client_id,
            current_memory=memory,
            recent_insight=recent_insight,
            storage=storage
        )

        response = ClientOverviewResponse(
            client_id=client_id,
            last_meeting_date=last_meeting_date,
            **report.model_dump()
        )

        # Cache the response
        if redis_pool:
            await redis_pool.setex(
                cache_key,
                3600, # 1 hour
                response.model_dump_json()
            )

        return response
    except HTTPException as he:
        raise he
    except Exception as e:
        logger.error(f"Error serving client overview: {e}")
        raise HTTPException(status_code=500, detail=str(e))
