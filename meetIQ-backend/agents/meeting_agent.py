from __future__ import annotations

import json
import os
import re
import uuid
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

import logging

from models.schemas import MeetingOutput
logger = logging.getLogger(__name__)

try:
    from dotenv import load_dotenv  # type: ignore

    load_dotenv()
except Exception:
    pass


try:
    from google.adk.agents import Agent  # type: ignore
    from google.adk.runners import InMemoryRunner  # type: ignore
    from google.genai.types import Content, Part  # type: ignore

    _ADK_AVAILABLE = True
except Exception:
    _ADK_AVAILABLE = False

    @dataclass
    class Agent:  # type: ignore
        model: str
        name: str
        description: str
        instruction: str
        global_instruction: str
        tools: List[Any]
        sub_agents: List[Any]


class MeetingAgent:
    def __init__(self) -> None:
        self.instructions = (
            "You are a professional meeting intelligence assistant built for financial advisors. "
            "Your job is to analyze a client-advisor conversation transcript and generate insights "
            "ONLY if the conversation is related to: Mutual Funds, SIP/Lumpsum, STP/SWP, "
            "Equity/Debt/Hybrid funds, or any regulated financial investment product. "
            "If the transcript explicitly mentions mutual fund, SIP, STP, SWP, equity, debt, hybrid, "
            "or fund, you MUST set is_financial_meeting=true and list those products. "
            "IMPORTANT FILTER RULES: If NOT related, return an empty but valid JSON response. "
            "Do NOT hallucinate financial intent. Use only what is explicitly or implicitly present. "
            "TASKS: Identify financial products discussed, understand client intent, summarize the "
            "conversation in advisor-friendly language, extract actionable next steps, and detect "
            "follow-up timing if mentioned. OUTPUT RULES: Respond in VALID JSON only, no markdown, "
            "no extra text. OUTPUT FORMAT: {"
            "\"is_financial_meeting\":true|false,"
            "\"financial_products\":[...],"
            "\"client_intent\":\"...\","
            "\"meeting_summary\":[...],"
            "\"action_items\":[...],"
            "\"follow_up_date\":\"YYYY-MM-DD\"|null,"
            "\"confidence_level\":\"high|medium|low\""
            "}. meeting_summary must be 3-5 bullets."
        )
        self.model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
        self.agent = Agent(
            model=self.model,
            name="MeetingAgent",
            description="Generate a concise meeting summary, action items, and follow-up date.",
            instruction=self.instructions,
            global_instruction=self.instructions,
            output_schema=MeetingOutput,
            tools=[],
            sub_agents=[],
        )

    async def run(self, transcript: str) -> MeetingOutput:
        if not transcript or not transcript.strip():
            return self._empty_output()

        content = await self._call_llm(transcript)
        parsed = self._parse_json(content)
        return self._normalize_output(parsed)

    async def _call_llm(self, transcript: str) -> str:
        use_vertex = os.getenv("GOOGLE_GENAI_USE_VERTEXAI", "").lower() in {"1", "true", "yes"}
        api_key = os.getenv("GEMINI_API_KEY") or os.getenv("GOOGLE_API_KEY")
        if not use_vertex and not api_key:
            return json.dumps(self._empty_payload())

        if not use_vertex and os.getenv("GOOGLE_API_KEY") is None and api_key:
            os.environ["GOOGLE_API_KEY"] = api_key

        prompt = (
            "Transcript:\n"
            f"{transcript}\n\n"
            "Return JSON only with schema: {"
            "\"is_financial_meeting\":false,"
            "\"financial_products\":[],"
            "\"client_intent\":\"\","
            "\"meeting_summary\":[],"
            "\"action_items\":[],"
            "\"follow_up_date\":null,"
            "\"confidence_level\":\"low\""
            "}"
        )

        if not _ADK_AVAILABLE:
            return json.dumps(self._empty_payload())

        adk_result = await self._run_adk_agent(prompt)
        if adk_result:
            return adk_result
        return json.dumps(self._empty_payload())

    async def _run_adk_agent(self, prompt: str) -> str:
        try:
            app_name = "meetiq"
            user_id = "meetiq"
            session_id = str(uuid.uuid4())
            runner = InMemoryRunner(agent=self.agent, app_name=app_name)
            runner.session_service.create_session_sync(
                app_name=app_name,
                user_id=user_id,
                session_id=session_id,
            )
            content = Content(role="user", parts=[Part(text=prompt)])
            stream = runner.run_async(
                user_id=user_id,
                session_id=session_id,
                new_message=content,
            )
            return await self._collect_adk_text(stream)
            if hasattr(self.agent, "arun"):
                result = await self.agent.arun(prompt)  # type: ignore[attr-defined]
                return self._extract_text(result)
            if hasattr(self.agent, "run"):
                maybe_result = self.agent.run(prompt)  # type: ignore[attr-defined]
                return await self._maybe_await(maybe_result)
            if hasattr(self.agent, "invoke"):
                maybe_result = self.agent.invoke(prompt)  # type: ignore[attr-defined]
                return await self._maybe_await(maybe_result)
        except Exception:
            logger.exception("ADK execution failed")
            return ""
        return ""

    async def _collect_adk_text(self, stream: Any) -> str:
        chunks: List[str] = []
        async for event in stream:
            content = getattr(event, "content", None)
            if content and getattr(content, "parts", None):
                for part in content.parts:
                    text = getattr(part, "text", "")
                    if text:
                        chunks.append(text)
        return "".join(chunks)

    async def _maybe_await(self, value: Any) -> str:
        if hasattr(value, "__await__"):
            result = await value
            return self._extract_text(result)
        return self._extract_text(value)

    def _extract_text(self, result: Any) -> str:
        if result is None:
            return ""
        if isinstance(result, str):
            return result
        if isinstance(result, dict):
            for key in ("text", "output", "content"):
                if key in result and isinstance(result[key], str):
                    return result[key]
        return str(result)

    def _parse_json(self, content: str) -> Dict[str, Any]:
        if not content:
            return {}
        try:
            return json.loads(content)
        except Exception:
            match = re.search(r"\{.*\}", content, re.DOTALL)
            if not match:
                return {}
            try:
                return json.loads(match.group(0))
            except Exception:
                return {}

    def _normalize_output(self, payload: Dict[str, Any]) -> MeetingOutput:
        is_financial_meeting = bool(payload.get("is_financial_meeting", False)) if isinstance(payload, dict) else False
        financial_products = payload.get("financial_products", []) if isinstance(payload, dict) else []
        client_intent = payload.get("client_intent", "") if isinstance(payload, dict) else ""
        meeting_summary = payload.get("meeting_summary", []) if isinstance(payload, dict) else []
        action_items = payload.get("action_items", []) if isinstance(payload, dict) else []
        follow_up_date = payload.get("follow_up_date", None) if isinstance(payload, dict) else None
        confidence_level = payload.get("confidence_level", "low") if isinstance(payload, dict) else "low"

        financial_products = [str(item).strip() for item in financial_products if str(item).strip()]
        meeting_summary = [str(item).strip() for item in meeting_summary if str(item).strip()]
        action_items = [str(item).strip() for item in action_items if str(item).strip()]
        client_intent = str(client_intent).strip()

        if len(meeting_summary) > 5:
            meeting_summary = meeting_summary[:5]
        while 0 < len(meeting_summary) < 3:
            meeting_summary.append("No additional details provided.")

        if not self._is_iso_date(follow_up_date):
            follow_up_date = None

        if confidence_level not in {"high", "medium", "low"}:
            confidence_level = "low"

        if not is_financial_meeting:
            return MeetingOutput(
                is_financial_meeting=False,
                financial_products=[],
                client_intent="",
                meeting_summary=[],
                action_items=[],
                follow_up_date=None,
                confidence_level="low",
            )

        return MeetingOutput(
            is_financial_meeting=True,
            financial_products=financial_products,
            client_intent=client_intent,
            meeting_summary=meeting_summary,
            action_items=action_items,
            follow_up_date=follow_up_date,
            confidence_level=confidence_level,
        )

    def _empty_payload(self) -> Dict[str, Any]:
        return {
            "is_financial_meeting": False,
            "financial_products": [],
            "client_intent": "",
            "meeting_summary": [],
            "action_items": [],
            "follow_up_date": None,
            "confidence_level": "low",
        }

    def _is_iso_date(self, value: Optional[str]) -> bool:
        if not isinstance(value, str):
            return False
        return re.fullmatch(r"\d{4}-\d{2}-\d{2}", value) is not None

    def _empty_output(self) -> MeetingOutput:
        return MeetingOutput(
            is_financial_meeting=False,
            financial_products=[],
            client_intent="",
            meeting_summary=[],
            action_items=[],
            follow_up_date=None,
            confidence_level="low",
        )
