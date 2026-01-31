import json
import logging
from typing import Optional, Any, Dict
from google import genai
from google.genai import types
from ..models.schemas import ClientMemory, MeetingInsight
from ..services.storage import StorageService
from ..services.toolbox_service import ToolboxService

logger = logging.getLogger(__name__)

class ClientOverviewAgent:
    """
    Specialized agent for generating rich, advisor-ready client overviews.
    
    This agent analyzes historical meeting patterns and current memory state 
    to produce a concise 500-character narrative summary that captures:
    - Client identity, role, and situation
    - Key financial characteristics and behavior patterns
    - Primary goals, concerns, and decision-making trends
    """
    
    def __init__(
        self, 
        api_key: Optional[str], 
        model_name: str = "gemini-2.5-flash",
        toolbox_service: Optional[ToolboxService] = None
    ):
        self.model_name = model_name
        self.toolbox = toolbox_service
        
        if api_key:
            self.client = genai.Client(api_key=api_key)
        else:
            self.client = None
            logger.warning("Gemini API key missing; client overview generation will be skipped.")

    async def generate_overview(
        self,
        client_id: str,
        current_memory: ClientMemory,
        recent_insight: MeetingInsight,
        storage: StorageService,
        max_history: int = 10
    ) -> str:
        """
        Generate a comprehensive client overview based on memory and meeting history.
        
        Args:
            client_id: The client's unique identifier
            current_memory: Current state of client memory
            recent_insight: The most recent meeting insight
            storage: StorageService instance for loading historical data
            max_history: Maximum number of recent meetings to analyze (default: 10)
            
        Returns:
            A concise narrative overview
        """
        logger.info(f"Generating client overview for {client_id}...")

        if not self.client:
            logger.warning("Skipping overview generation - no API key")
            # Return a basic fallback overview from memory
            if current_memory.profile:
                profile_summary = ", ".join([f"{k}: {v}" for k, v in list(current_memory.profile.items())[:3]])
                return f"Client profile: {profile_summary}"
            return f"Client {client_id}"

        # Load historical meeting insights
        meeting_ids = storage.list_meeting_ids(client_id)
        logger.info(f"Found {len(meeting_ids)} meetings for client {client_id}")
        
        # Get the most recent meetings (limit to max_history)
        recent_meeting_ids = sorted(meeting_ids, reverse=True)[:max_history]
        historical_insights = []
        
        for mid in recent_meeting_ids:
            insight = storage.load_meeting_insight(client_id, mid)
            if insight:
                historical_insights.append(insight)
        
        logger.info(f"Loaded {len(historical_insights)} historical insights for analysis")

        # Enrich with toolbox data (goal details, scheme info)
        enriched_context = await self._fetch_enrichment_data(current_memory)

        # Prepare context for the LLM
        memory_json = current_memory.model_dump_json()
        recent_insight_json = recent_insight.model_dump_json()
        
        # Summarize historical insights
        historical_summary = self._summarize_historical_insights(historical_insights)

        # Build enrichment section for prompt
        enrichment_section = ""
        if enriched_context:
            enrichment_section = f"""
4. ENRICHED GOAL/SCHEME DETAILS (from system):
{json.dumps(enriched_context, indent=2, default=str)}
"""

        prompt = f"""
You are a specialized 'Client Overview Generator' for a financial advisor system.

Your ONLY task is to create a concise, insightful client narrative that an advisor can read in 5 seconds to understand who the client is.

CRITICAL REQUIREMENTS:
1. Output MUST be between 20-30 words
2. Write in third person, professional tone
3. Focus on the most salient, actionable insights
4. Prioritize PATTERNS over one-time events
5. Include: identity/situation, financial behavior, key goals, decision-making style
6. Output ONLY the narrative text - no JSON, no quotes, no formatting
7. MUST be complete sentences - never end mid-sentence
8. If enriched goal/scheme details are provided, incorporate relevant scheme names or goal sub-types

STRUCTURE (2-3 complete sentences):
- Sentence 1: Who they are (role, life stage, situation)
- Sentence 2: Financial characteristics/behavior (risk profile, products, patterns)
- Sentence 3: Goals and current trajectory

INPUTS:

1. CURRENT MEMORY (Authoritative):
{memory_json}

2. MOST RECENT MEETING:
{recent_insight_json}

3. HISTORICAL MEETING PATTERNS (Last {len(historical_insights)} meetings):
{historical_summary}
{enrichment_section}
EXAMPLE OUTPUT (follow this exact format):
Senior executive, 45, planning early retirement. Conservative investor with 60% equity exposure, regularly discusses retirement funds and tax-advantaged accounts. Primary goal is to retire by 55 with $5M portfolio, showing increasing confidence after recent reviews.

Generate the client overview now (100-500 chars, complete sentences only):"""

        try:
            response = self.client.models.generate_content(
                model=self.model_name,
                contents=prompt,
                config=types.GenerateContentConfig(
                    temperature=0.7
                )
            )
            
            overview = response.text.strip()
            
            # Remove any markdown formatting or quotes if present
            overview = overview.strip('"\'`')
            
            # Validate the overview is complete (not truncated mid-sentence)
            if overview and len(overview) < 50:
                logger.warning(f"Overview too short ({len(overview)} chars), regenerating with fallback")
                return self._generate_fallback_overview(current_memory)
            
            # Check for incomplete sentences (ending with incomplete words)
            if overview and not overview[-1] in '.!?"\'':
                # Try to find the last complete sentence
                last_period = overview.rfind('.')
                last_exclaim = overview.rfind('!')
                last_question = overview.rfind('?')
                last_complete = max(last_period, last_exclaim, last_question)
                
                if last_complete > 50:  # Ensure we have at least some content
                    overview = overview[:last_complete + 1]
                    logger.warning(f"Truncated incomplete sentence, now {len(overview)} chars")
            
            # Enforce 500 character limit
            if len(overview) > 500:
                # Truncate at last complete sentence within limit
                truncated = overview[:500]
                last_period = truncated.rfind('.')
                if last_period > 300:
                    overview = truncated[:last_period + 1]
                else:
                    overview = truncated[:497] + "..."
                logger.warning(f"Overview truncated to {len(overview)} characters")
            
            logger.info(f"Generated overview ({len(overview)} chars): {overview[:100]}...")
            return overview
            
        except Exception as e:
            logger.error(f"Error generating client overview: {e}")
            # Fallback to a basic overview from memory
            return self._generate_fallback_overview(current_memory)

    def _summarize_historical_insights(self, insights: list[MeetingInsight]) -> str:
        """
        Create a compact summary of historical meeting insights for the prompt.
        """
        if not insights:
            return "No prior meetings available."
        
        summary_lines = []
        product_mentions = {}
        intent_patterns = []
        
        for idx, insight in enumerate(insights[:10]):  # Limit to most recent 10
            # Track product mentions
            for product in insight.financial_products:
                product_mentions[product] = product_mentions.get(product, 0) + 1
            
            # Collect intents
            if insight.client_intent:
                intent_patterns.append(insight.client_intent)
        
        # Build summary
        summary_lines.append(f"Total meetings analyzed: {len(insights)}")
        
        if product_mentions:
            top_products = sorted(product_mentions.items(), key=lambda x: x[1], reverse=True)[:3]
            products_str = ", ".join([f"{prod} ({count}x)" for prod, count in top_products])
            summary_lines.append(f"Most discussed products: {products_str}")
        
        if intent_patterns:
            recent_intents = intent_patterns[:3]
            summary_lines.append(f"Recent intents: {'; '.join(recent_intents)}")
        
        return "\n".join(summary_lines)

    def _generate_fallback_overview(self, memory: ClientMemory) -> str:
        """
        Generate a basic overview when LLM is unavailable or fails.
        """
        parts = []
        
        # Profile info
        if memory.profile:
            profile_items = [f"{k}: {v}" for k, v in list(memory.profile.items())[:2]]
            if profile_items:
                parts.append(", ".join(profile_items))
        
        # Goals
        if memory.active_financial_goals:
            goals_str = ", ".join([g.name for g in memory.active_financial_goals[:2]])
            parts.append(f"Goals: {goals_str}")
        
        # Products
        if memory.discussed_products:
            top_products = sorted(memory.discussed_products.items(), key=lambda x: x[1], reverse=True)[:2]
            products_str = ", ".join([prod for prod, _ in top_products])
            parts.append(f"Interested in: {products_str}")
        
        # Risk profile
        if memory.risk_profile:
            parts.append(f"Risk profile: {memory.risk_profile}")
        
        overview = ". ".join(parts)
        if len(overview) > 500:
            overview = overview[:497] + "..."
        
        return overview if overview else f"Client {memory.client_id}"

    async def _fetch_enrichment_data(self, memory: ClientMemory) -> Dict[str, Any]:
        """
        Fetch enriched data from toolbox for goals and schemes.
        
        Args:
            memory: Current client memory
            
        Returns:
            Dict containing enriched goal/scheme details
        """
        if not self.toolbox or not self.toolbox.is_available:
            logger.debug("Toolbox not available, skipping enrichment")
            return {}
        
        enriched = {}
        
        try:
            # Fetch all user goals using the client_id (sanitized by service)
            user_goals = await self.toolbox.get_user_goals(memory.client_id)
            
            if user_goals:
                # Handle potentially large response
                processed_goals = self._process_large_toolbox_data(user_goals)
                if processed_goals:
                    enriched["user_portfolio_goals"] = processed_goals
                    logger.info("Enriched with user portfolio data from toolbox")
            
        except Exception as e:
            logger.error(f"Error fetching enrichment data: {e}")
        
        return enriched

    def _process_large_toolbox_data(self, data: Any, max_items: int = 5) -> Any:
        """
        Process and truncate large toolbox responses to safe-guard LLM context.
        """
        # If string JSON, parse it
        if isinstance(data, str):
            try:
                data = json.loads(data)
            except Exception:
                # If raw string, just truncate
                return data[:1000] + "..." if len(data) > 1000 else data

        # If list, take top N
        if isinstance(data, list):
            return data[:max_items]
            
        # If dict, we're probably okay, but safeguards are good
        if isinstance(data, dict) and len(str(data)) > 5000:
             return {"data_summary": "Response too large to process fully"}
             
        return data
