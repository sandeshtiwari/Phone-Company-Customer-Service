from __future__ import annotations

from typing import Any

from agents.mcp import MCPServer

from .demo_trace import DemoTraceRecorder


class AliasedMCPServer(MCPServer):
    """Present transport-safe tool names without changing Runner's MCP surface."""

    def __init__(
        self,
        inner: MCPServer,
        aliases: dict[str, str],
        trace_recorder: DemoTraceRecorder | None = None,
    ) -> None:
        super().__init__(use_structured_content=inner.use_structured_content)
        self._inner = inner
        self._aliases = aliases
        self._canonical_names = {alias: canonical for canonical, alias in aliases.items()}
        self._cached_tools: list[Any] | None = None
        self._trace_recorder = trace_recorder

    @property
    def name(self) -> str:
        return self._inner.name

    @property
    def cached_tools(self) -> list[Any] | None:
        return self._cached_tools

    async def __aenter__(self):
        await self.connect()
        return self

    async def __aexit__(self, exc_type, exc_value, traceback):
        await self.cleanup()

    async def connect(self):
        return await self._inner.connect()

    async def cleanup(self):
        return await self._inner.cleanup()

    async def list_tools(self, run_context=None, agent=None):
        tools = await self._inner.list_tools(run_context=run_context, agent=agent)
        self._cached_tools = [
            tool.model_copy(update={"name": self._aliases.get(tool.name, tool.name)})
            for tool in tools
        ]
        if self._trace_recorder:
            self._trace_recorder.record_tool_catalog(
                server=self.name,
                canonical_tools=tools,
                model_tools=self._cached_tools,
            )
        return self._cached_tools

    async def call_tool(self, tool_name: str, arguments: dict[str, Any] | None, meta=None):
        canonical_name = self._canonical_names.get(tool_name, tool_name)
        if not self._trace_recorder:
            return await self._inner.call_tool(canonical_name, arguments, meta)
        call_id = self._trace_recorder.tool_call_started(
            server=self.name,
            model_tool_name=tool_name,
            runner_tool_name=canonical_name,
            arguments=arguments,
        )
        try:
            result = await self._inner.call_tool(canonical_name, arguments, meta)
        except Exception as exc:
            self._trace_recorder.tool_call_failed(call_id, exc)
            raise
        self._trace_recorder.tool_call_finished(call_id, result)
        return result

    async def list_prompts(self):
        return await self._inner.list_prompts()

    async def get_prompt(self, name: str, arguments: dict[str, Any] | None = None):
        return await self._inner.get_prompt(name, arguments)
