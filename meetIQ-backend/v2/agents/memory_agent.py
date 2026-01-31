import json
import logging
from typing import Optional
from google import genai
from google.genai import types
from ..models.schemas import ClientMemory, MeetingInsight

logger = logging.getLogger(__name__)

class MemoryAgent:
    def __init__(self, api_key: Optional[str], model_name: str = "gemini-2.5-flash"):
        self.model_name = model_name
        if api_key:
            self.client = genai.Client(api_key=api_key)
        else:
            self.client = None
            logger.warning("Gemini API key missing; skipping memory update.")

    async def update_memory(self, current_memory: ClientMemory, meeting_insight: MeetingInsight) -> ClientMemory:
        logger.info(f"Updating memory for client {current_memory.client_id}...")

        if not self.client:
            return current_memory

        # Convert objects to JSON for the prompt
        memory_json = current_memory.model_dump_json()
        insight_json = meeting_insight.model_dump_json()

        prompt = f"""
        You are the 'Client Memory Manager' for a financial advisor system.
        Your job is to update the long-term memory of a client based on NEW insights from a recent meeting.
        
        CRITICAL RULES:
        1. Memory is opinionated, slow-changing, and validated.
        2. Do NOT simply append the new meeting summary.
        3. Do NOT store one-off emotional statements unless they form a pattern.
        4. Update 'active_financial_goals' only if the client explicitly confirms or adds one. Each goal must be an object with 'name' and 'status'.
        5. Update 'discussed_products' by incrementing counts.
        6. Determine 'decision_confidence_trend' by comparing current sentiment to past behavior.
           ALLOWED VALUES: "increasing", "stable", "decreasing".
        7. 'pending_action_items' should be a merged list of old incomplete items + new ones (remove completed).
        8. PRESERVE the existing 'client_overview' field as-is. Do NOT modify it - this is handled by a specialized agent.
        
        INPUTS:
        
        1. EXISTING MEMORY (Authoritative):
        {memory_json}
        
        2. NEW MEETING INSIGHT (New Evidence):
        {insight_json}
        
        TASK:
        Generate the NEW ClientMemory JSON object merging the insights into the memory.
        
        REQUIRED FIELDS TO UPDATE:
        - profile: Extract any personal/professional details mentioned.
        - active_financial_goals, discussed_products, decision_confidence_trend, etc.
        - client_overview: PRESERVE the existing value, do not generate or modify.
        
        Return ONLY valid JSON matching the ClientMemory schema.
        """

        try:
            response = self.client.models.generate_content(
                model=self.model_name,
                contents=prompt,
                config=types.GenerateContentConfig(response_mime_type="application/json")
            )
            
            data = json.loads(response.text)

            # Sanitize fields to match Literal constraints
            # decision_confidence_trend
            valid_trends = ["increasing", "stable", "decreasing"]
            trend = data.get("decision_confidence_trend")
            if trend not in valid_trends:
                if trend == "positive":
                    data["decision_confidence_trend"] = "increasing"
                elif trend == "negative":
                    data["decision_confidence_trend"] = "decreasing"
                else:
                    data["decision_confidence_trend"] = "stable"

            # engagement_level
            valid_engagement = ["high", "medium", "low"]
            engagement = data.get("engagement_level")
            if engagement not in valid_engagement:
                data["engagement_level"] = "medium"  # Default fallback

            # memory_confidence
            valid_confidence = ["high", "medium", "low"]
            confidence = data.get("memory_confidence")
            if confidence not in valid_confidence:
                 data["memory_confidence"] = "medium" # Default fallback
            
            # Fix profile field: ensure all values are strings (convert int to str)
            if "profile" in data and isinstance(data["profile"], dict):
                data["profile"] = {k: str(v) if v is not None else "" for k, v in data["profile"].items()}
            
            # Preserve existing client_overview if model removes it
            if "client_overview" not in data or data["client_overview"] is None:
                data["client_overview"] = current_memory.client_overview
            
            # Fix risk_profile: if it's a dict, convert to string representation or extract text
            if "risk_profile" in data and isinstance(data["risk_profile"], dict):
                # Convert dict to a descriptive string
                if "risk_aversion" in data["risk_profile"]:
                    data["risk_profile"] = str(data["risk_profile"])
                else:
                    data["risk_profile"] = json.dumps(data["risk_profile"])
            
            # Ensure critical fields are preserved if model halllucinated them away (optional safety)
            # data['client_id'] = current_memory.client_id 
            
            return ClientMemory(**data)
            
        except Exception as e:
            logger.error(f"Error updating memory: {e}")
            raise e
