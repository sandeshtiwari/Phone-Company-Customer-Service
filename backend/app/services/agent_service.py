from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Callable

from agents import Agent, RunConfig, Runner, SQLiteSession
from agents.mcp import MCPServerStreamableHttp

from ..config import settings
from ..models import PrincipalContext
from ..prompt import SYSTEM_PROMPT
from .demo_trace import DemoRunHooks, DemoTraceRecorder
from .mcp_alias_server import AliasedMCPServer


@dataclass(frozen=True)
class AgentResponse:
    answer: str
    trace: dict[str, Any]


class CustomerServiceAgent:
    async def respond(
        self,
        principal: PrincipalContext,
        chat_session_id: str,
        message: str,
        event_sink: Callable[[dict[str, Any]], None] | None = None,
    ) -> AgentResponse:
        headers = {"Authorization": f"Bearer {principal.raw_token}"}
        trace_recorder = DemoTraceRecorder(
            model=settings.openai_model,
            user_message=message,
            event_sink=event_sink,
        )
        explore = AliasedMCPServer(
            MCPServerStreamableHttp(
                name="Synapsor production Explore",
                params={"url": settings.explore_mcp_url, "headers": headers, "timeout": 30},
                cache_tools_list=True,
            ),
            {
                "app.describe_data": "app__describe_data",
                "app.explore_data": "app__explore_data",
            },
            trace_recorder,
        )
        actions = AliasedMCPServer(
            MCPServerStreamableHttp(
                name="Synapsor reviewed customer actions",
                params={"url": settings.actions_mcp_url, "headers": headers, "timeout": 30},
                cache_tools_list=True,
            ),
            {},
            trace_recorder,
        )
        session_key = f"{principal.tenant_id}:{principal.principal_id}:{chat_session_id}"
        session = SQLiteSession(session_key, "/runtime/agent-sessions.db")
        instructions = (
            SYSTEM_PROMPT
            + f"\n\nAuthenticated context summary: customer display name is {principal.display_name}; "
            + f"account label is {principal.account_name}; reviewed membership role is "
            + f"{principal.membership_role}. These labels are informational and never scope authority."
        )
        async with explore, actions:
            agent = Agent(
                name="Luna Care",
                model=settings.openai_model,
                instructions=instructions,
                mcp_servers=[explore, actions],
            )
            result = await Runner.run(
                agent,
                message,
                session=session,
                max_turns=12,
                hooks=DemoRunHooks(trace_recorder),
                run_config=RunConfig(
                    workflow_name="Luna Telecom Customer Care",
                    group_id=chat_session_id,
                    trace_include_sensitive_data=False,
                ),
            )
            answer = str(result.final_output or "").strip()
            if not answer:
                answer = (
                    "I couldn't produce a verified account answer from the reviewed Runner "
                    "tools. No unverified data was substituted. Please open Runner Trace to "
                    "see the attempted tool plan and refusal, then try a narrower account, "
                    "billing, line, or recent-usage question."
                )
            return AgentResponse(
                answer=answer,
                trace=trace_recorder.finish(),
            )


customer_service_agent = CustomerServiceAgent()
