from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from models.schemas import MeetingOutput


try:
    from google.adk.agents import Agent  # type: ignore

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
            "Analyze the transcript ONLY if it is about regulated financial investment products "
            "(Mutual Funds, SIP/Lumpsum, STP/SWP, Equity/Debt/Hybrid funds or similar). "
            "If not related, return an empty but valid JSON with is_financial_meeting=false. "
            "Do not hallucinate. Use only what is present in the transcript. "
            "Return VALID JSON only with keys: is_financial_meeting, financial_products, "
            "client_intent, meeting_summary, action_items, follow_up_date, confidence_level. "
            "meeting_summary must be 3-5 bullets. follow_up_date must be YYYY-MM-DD or null. "
            "confidence_level must be high, medium, or low. No markdown."
        )
        self.model = os.getenv("GEMINI_MODEL", "gemini-2.5-flash")
        self.agent = Agent(
            model=self.model,
            name="MeetingAgent",
            description="Generate a concise meeting summary, action items, and follow-up date.",
            instruction=self.instructions,
            global_instruction=self.instructions,
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
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            return json.dumps(self._heuristic_output(transcript))

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
            return json.dumps(self._heuristic_output(transcript))

        adk_result = await self._run_adk_agent(prompt)
        if adk_result:
            return adk_result
        return json.dumps(self._heuristic_output(transcript))

    async def _run_adk_agent(self, prompt: str) -> str:
        try:
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
            return ""
        return ""

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

    def _heuristic_output(self, transcript: str) -> Dict[str, Any]:
        lower = transcript.lower()
        is_financial = any(
            keyword in lower
            for keyword in [
                "mutual fund",
                "sip",
                "lumpsum",
                "stp",
                "swp",
                "equity",
                "debt",
                "hybrid",
                "fund",
            ]
        )

        if not is_financial:
            return {
                "is_financial_meeting": False,
                "financial_products": [],
                "client_intent": "",
                "meeting_summary": [],
                "action_items": [],
                "follow_up_date": None,
                "confidence_level": "low",
            }

        products: List[str] = []
        if "mutual fund" in lower or "mutual funds" in lower:
            products.append("Mutual Fund")
        if "sip" in lower:
            products.append("SIP")
        if "lumpsum" in lower or "lump sum" in lower:
            products.append("Lumpsum")
        if "stp" in lower:
            products.append("STP")
        if "swp" in lower:
            products.append("SWP")
        if "equity" in lower:
            products.append("Equity Fund")
        if "debt" in lower:
            products.append("Debt Fund")
        if "hybrid" in lower:
            products.append("Hybrid Fund")

        amount_match = re.search(r"(?:₹|rs\.?|inr)\s*(\d[\d,]*)", lower)
        amount = amount_match.group(1) if amount_match else ""
        if amount:
            amount = amount.replace(",", "")
        duration_match = re.search(r"(\d+)\s*(?:year|years|yr|yrs)", lower)
        duration_years = duration_match.group(1) if duration_match else ""

        intent = "Advisor discussed a financial investment option"
        if "sip" in lower and "mutual fund" in lower:
            intent = "Advisor explained a long-term SIP investment opportunity in mutual funds"
        elif "sip" in lower:
            intent = "Advisor discussed starting a SIP investment"
        elif "mutual fund" in lower:
            intent = "Advisor discussed a mutual fund investment option"

        meeting_summary: List[str] = []
        if "mutual fund" in lower:
            meeting_summary.append("Advisor introduced a mutual fund investment option to the client")
        if "sip" in lower and (amount or duration_years):
            if amount and duration_years:
                meeting_summary.append(
                    f"A SIP of ₹{amount} per month for a period of {duration_years} years was discussed"
                )
            elif amount:
                meeting_summary.append(f"A SIP of ₹{amount} per month was discussed")
            elif duration_years:
                meeting_summary.append(f"A SIP duration of {duration_years} years was discussed")
        if "one crore" in lower or "crore" in lower or "returns" in lower or "grow" in lower:
            meeting_summary.append(
                "Advisor indicated the investment could grow over time based on expected returns"
            )

        if not meeting_summary:
            sentences = [s.strip() for s in re.split(r"[.!?]\s+", transcript) if s.strip()]
            meeting_summary = sentences[:5]

        if len(meeting_summary) > 5:
            meeting_summary = meeting_summary[:5]
        while 0 < len(meeting_summary) < 3:
            meeting_summary.append("No additional details provided.")

        action_items = [
            "Explain realistic return assumptions and risks associated with the investment",
            "Share a detailed proposal with projected returns",
            "Confirm client interest before proceeding",
        ]

        return {
            "is_financial_meeting": True,
            "financial_products": products,
            "client_intent": intent,
            "meeting_summary": meeting_summary,
            "action_items": action_items,
            "follow_up_date": None,
            "confidence_level": "medium",
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
