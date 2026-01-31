import json
import logging
from typing import Optional
from google import genai
from google.genai import types
from ..models.schemas import MeetingInsight

logger = logging.getLogger(__name__)


class EmailDraft:
    """Model for email draft response"""
    def __init__(
        self,
        subject: str,
        body: str,
        suggested_attachments: list[str] = None,
        tone: str = "professional"
    ):
        self.subject = subject
        self.body = body
        self.suggested_attachments = suggested_attachments or []
        self.tone = tone
    
    def to_dict(self) -> dict:
        return {
            "subject": self.subject,
            "body": self.body,
            "suggested_attachments": self.suggested_attachments,
            "tone": self.tone
        }


class EmailDraftAgent:
    """
    Agent for generating professional email drafts from meeting insights.
    
    This agent takes meeting analysis results and creates a well-structured
    email that a financial advisor/partner can send to their client summarizing
    the meeting and outlining next steps.
    """
    
    def __init__(self, api_key: Optional[str], model_name: str = "gemini-2.5-flash"):
        self.model_name = model_name
        if api_key:
            self.client = genai.Client(api_key=api_key)
        else:
            self.client = None
            logger.warning("Gemini API key missing; email draft generation will be skipped.")

    def _empty_draft(self) -> EmailDraft:
        return EmailDraft(
            subject="Meeting Follow-up",
            body="Thank you for your time today. Please find the meeting summary attached.",
            suggested_attachments=[],
            tone="professional"
        )

    async def generate_draft(
        self,
        meeting_insight: MeetingInsight,
        client_name: Optional[str] = None,
        partner_name: Optional[str] = None,
        transcript: Optional[str] = None
    ) -> EmailDraft:
        """
        Generate an email draft based on meeting insights.
        
        Args:
            meeting_insight: The analyzed meeting insight data
            client_name: Optional client name for personalization
            partner_name: Optional partner/advisor name for signature
            transcript: Optional transcript for additional context
            
        Returns:
            EmailDraft object with subject, body, and suggestions
        """
        logger.info(f"Generating email draft for meeting {meeting_insight.meeting_id}...")

        if not self.client:
            logger.warning("Skipping email draft generation - no API key")
            return self._empty_draft()
        
        # Build context from meeting insight
        insight_json = meeting_insight.model_dump_json()
        
        # Personalization
        client_greeting = f"Dear {client_name}" if client_name else "Dear Valued Client"
        partner_signature = partner_name if partner_name else "Your Financial Advisor"
        
        prompt = f"""
You are a professional email writer for financial advisors. Your task is to create a clear, 
warm, and professional follow-up email that a financial advisor can send to their client 
after a meeting.

MEETING ANALYSIS:
{insight_json}

PERSONALIZATION:
- Client greeting: {client_greeting}
- Advisor signature: {partner_signature}

REQUIREMENTS:
1. Write in a warm but professional tone
2. Start with appreciation for the client's time
3. Summarize the key discussion points from the meeting
4. Clearly list any action items for both parties
5. Mention follow-up items and any scheduled next steps
6. If financial products were discussed, mention them naturally
7. End with an encouraging note and clear next steps
8. Keep the email concise but comprehensive (200-400 words ideal)

OUTPUT FORMAT (Return ONLY valid JSON):
{{
    "subject": "string - compelling email subject line",
    "body": "string - the complete email body with proper formatting (use \\n for line breaks)",
    "suggested_attachments": ["list of suggested documents to attach based on discussion"],
    "tone": "professional" | "friendly" | "formal"
}}

Generate the email draft now:"""

        try:
            response = self.client.models.generate_content(
                model=self.model_name,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    temperature=0.7
                )
            )
            
            data = json.loads(response.text)
            
            return EmailDraft(
                subject=data.get("subject", "Meeting Follow-up"),
                body=data.get("body", ""),
                suggested_attachments=data.get("suggested_attachments", []),
                tone=data.get("tone", "professional")
            )
            
        except Exception as e:
            logger.error(f"Error generating email draft: {e}")
            # Return a fallback draft based on meeting insight
            return self._generate_fallback_draft(meeting_insight, client_greeting, partner_signature)

    def _generate_fallback_draft(
        self,
        insight: MeetingInsight,
        client_greeting: str,
        partner_signature: str
    ) -> EmailDraft:
        """
        Generate a basic email draft when LLM is unavailable or fails.
        """
        # Build subject
        if insight.financial_products:
            subject = f"Follow-up: Discussion on {insight.financial_products[0]}"
        else:
            subject = "Follow-up: Our Recent Meeting"
        
        # Build body
        body_parts = [
            f"{client_greeting},\n",
            "Thank you for taking the time to meet with me today. I wanted to follow up on our discussion and summarize the key points.\n"
        ]
        
        # Add summary points
        if insight.meeting_summary:
            body_parts.append("\n**Meeting Summary:**")
            for point in insight.meeting_summary[:5]:
                body_parts.append(f"• {point}")
            body_parts.append("")
        
        # Add action items
        if insight.action_items:
            body_parts.append("\n**Action Items:**")
            for item in insight.action_items:
                body_parts.append(f"• {item}")
            body_parts.append("")
        
        # Add follow-ups
        if insight.follow_ups:
            body_parts.append("\n**Next Steps:**")
            for follow_up in insight.follow_ups:
                body_parts.append(f"• {follow_up}")
            body_parts.append("")
        
        # Add follow-up date if available
        if insight.follow_up_date:
            body_parts.append(f"\nI've noted our next meeting for {insight.follow_up_date}.")
        
        # Closing
        body_parts.extend([
            "\nPlease don't hesitate to reach out if you have any questions or need any clarification.",
            "\nBest regards,",
            partner_signature
        ])
        
        body = "\n".join(body_parts)
        
        # Suggest attachments based on products discussed
        attachments = []
        if insight.financial_products:
            for product in insight.financial_products[:3]:
                attachments.append(f"{product} - Product Brochure")
        if insight.action_items:
            attachments.append("Action Items Summary")
        
        return EmailDraft(
            subject=subject,
            body=body,
            suggested_attachments=attachments,
            tone="professional"
        )
