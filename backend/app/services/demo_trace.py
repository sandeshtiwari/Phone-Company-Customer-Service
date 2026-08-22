from __future__ import annotations

from dataclasses import asdict, dataclass, is_dataclass
from datetime import date, datetime, timezone
from enum import Enum
from time import perf_counter
from typing import Any, Callable
from uuid import UUID, uuid4

from agents import RunHooks


_SECRET_KEYS = {
    "access_token",
    "api_key",
    "authorization",
    "bearer_token",
    "database_url",
    "jwt",
    "password",
    "private_key",
    "raw_token",
    "refresh_token",
}


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _looks_secret(key: str) -> bool:
    normalized = key.lower().replace("-", "_")
    return (
        normalized in _SECRET_KEYS
        or normalized.endswith("_api_key")
        or normalized.endswith("_password")
        or normalized.endswith("_private_key")
        or normalized.endswith("_secret")
    )


def safe_json(value: Any, *, key: str = "") -> Any:
    """Convert SDK/MCP objects to browser-safe JSON while stripping credentials."""
    if key and _looks_secret(key):
        return "[redacted]"
    if value is None or isinstance(value, (str, int, float, bool)):
        return value
    if isinstance(value, (datetime, date, UUID, Enum)):
        return str(value.value if isinstance(value, Enum) else value)
    if hasattr(value, "model_dump"):
        return safe_json(value.model_dump(mode="json", exclude_none=True))
    if is_dataclass(value):
        return safe_json(asdict(value))
    if isinstance(value, dict):
        return {str(k): safe_json(v, key=str(k)) for k, v in value.items()}
    if isinstance(value, (list, tuple, set)):
        return [safe_json(item) for item in value]
    return repr(value)


@dataclass
class _OpenCall:
    event: dict[str, Any]
    started: float


class DemoTraceRecorder:
    """Request-local, ephemeral observability for the browser demonstration."""

    def __init__(
        self,
        *,
        model: str,
        user_message: str,
        event_sink: Callable[[dict[str, Any]], None] | None = None,
    ) -> None:
        self.trace_id = f"demo_{uuid4().hex}"
        self.model = model
        self.user_message = user_message
        self.started_at = _utc_now()
        self._started = perf_counter()
        self._catalogs: dict[str, dict[str, Any]] = {}
        self._model_turns: list[dict[str, Any]] = []
        self._tool_calls: list[dict[str, Any]] = []
        self._open_calls: dict[str, _OpenCall] = {}
        self._usage: dict[str, Any] | None = None
        self._events: list[dict[str, Any]] = []
        self._event_sink = event_sink
        self._emit(
            kind="trace.started",
            stage="system",
            title="Authenticated trace started",
            payload={"model": model, "user_message": user_message},
        )

    def _emit(
        self,
        *,
        kind: str,
        stage: str,
        title: str,
        payload: Any,
    ) -> None:
        event = {
            "sequence": len(self._events) + 1,
            "kind": kind,
            "stage": stage,
            "title": title,
            "offset_ms": round((perf_counter() - self._started) * 1000),
            "recorded_at": _utc_now(),
            "payload": safe_json(payload),
        }
        self._events.append(event)
        if self._event_sink:
            self._event_sink(event)

    def record_tool_catalog(
        self,
        *,
        server: str,
        canonical_tools: list[Any],
        model_tools: list[Any],
    ) -> None:
        if server in self._catalogs:
            return
        canonical_by_position = [getattr(tool, "name", "unknown") for tool in canonical_tools]
        visible: list[dict[str, Any]] = []
        for index, tool in enumerate(model_tools):
            dumped = safe_json(tool)
            visible.append(
                {
                    "model_tool_name": getattr(tool, "name", "unknown"),
                    "runner_tool_name": canonical_by_position[index],
                    "description": dumped.get("description") if isinstance(dumped, dict) else None,
                    "input_schema": (
                        dumped.get("inputSchema", dumped.get("input_schema"))
                        if isinstance(dumped, dict)
                        else None
                    ),
                }
            )
        self._catalogs[server] = {
            "server": server,
            "transport": "Streamable HTTP MCP",
            "tools": visible,
        }
        self._emit(
            kind="tools.catalog",
            stage="model",
            title=f"{server} tools exposed to the model",
            payload=self._catalogs[server],
        )

    def model_turn_started(self, *, system_prompt: str | None, input_items: list[Any]) -> None:
        turn = {
            "turn": len(self._model_turns) + 1,
            "started_at": _utc_now(),
            "system_prompt": system_prompt,
            "input_items": safe_json(input_items),
            "model_output": None,
        }
        self._model_turns.append(turn)
        self._emit(
            kind="model.started",
            stage="model",
            title=f"Model turn {turn['turn']} started",
            payload={
                "turn": turn["turn"],
                "system_prompt": system_prompt,
                "input_items": turn["input_items"],
            },
        )

    def model_turn_finished(self, response: Any, usage: Any) -> None:
        if self._model_turns:
            self._model_turns[-1]["model_output"] = safe_json(response)
            self._model_turns[-1]["finished_at"] = _utc_now()
        self._usage = safe_json(usage)
        turn_number = self._model_turns[-1]["turn"] if self._model_turns else 1
        self._emit(
            kind="model.completed",
            stage="model",
            title=f"Model turn {turn_number} completed",
            payload={"turn": turn_number, "model_output": response, "usage": usage},
        )

    def tool_call_started(
        self,
        *,
        server: str,
        model_tool_name: str,
        runner_tool_name: str,
        arguments: dict[str, Any] | None,
    ) -> str:
        call_id = f"tool_{uuid4().hex[:12]}"
        safe_arguments = safe_json(arguments or {})
        event = {
            "call_id": call_id,
            "sequence": len(self._tool_calls) + 1,
            "server": server,
            "transport": "Streamable HTTP MCP",
            "model_emitted": {
                "name": model_tool_name,
                "arguments": safe_arguments,
            },
            "runner_request": {
                "name": runner_tool_name,
                "arguments": safe_arguments,
            },
            "started_at": _utc_now(),
            "status": "running",
            "runner_response": None,
        }
        self._tool_calls.append(event)
        self._open_calls[call_id] = _OpenCall(event=event, started=perf_counter())
        self._emit(
            kind="runner.request",
            stage="runner",
            title=f"Runner received {runner_tool_name}",
            payload={
                "call_id": call_id,
                "server": server,
                "model_emitted": event["model_emitted"],
                "canonical_request": event["runner_request"],
            },
        )
        return call_id

    def tool_call_finished(self, call_id: str, result: Any) -> None:
        open_call = self._open_calls.pop(call_id)
        open_call.event.update(
            {
                "status": "ok",
                "runner_response": safe_json(result),
                "finished_at": _utc_now(),
                "duration_ms": round((perf_counter() - open_call.started) * 1000),
            }
        )
        self._emit(
            kind="runner.response",
            stage="response",
            title=f"Runner returned {open_call.event['runner_request']['name']}",
            payload={
                "call_id": call_id,
                "status": "ok",
                "duration_ms": open_call.event["duration_ms"],
                "response": open_call.event["runner_response"],
            },
        )

    def tool_call_failed(self, call_id: str, exc: Exception) -> None:
        open_call = self._open_calls.pop(call_id)
        open_call.event.update(
            {
                "status": "error",
                "runner_response": {
                    "error_type": type(exc).__name__,
                    "message": str(exc),
                },
                "finished_at": _utc_now(),
                "duration_ms": round((perf_counter() - open_call.started) * 1000),
            }
        )
        self._emit(
            kind="runner.error",
            stage="response",
            title=f"Runner rejected {open_call.event['runner_request']['name']}",
            payload={
                "call_id": call_id,
                "status": "error",
                "duration_ms": open_call.event["duration_ms"],
                "response": open_call.event["runner_response"],
            },
        )

    def finish(self) -> dict[str, Any]:
        summary = {
            "model_turns": len(self._model_turns),
            "runner_calls": len(self._tool_calls),
            "successful_calls": sum(call["status"] == "ok" for call in self._tool_calls),
            "failed_calls": sum(call["status"] == "error" for call in self._tool_calls),
        }
        self._emit(
            kind="trace.completed",
            stage="response",
            title="Authenticated trace completed",
            payload={
                "summary": summary,
                "duration_ms": round((perf_counter() - self._started) * 1000),
            },
        )
        return {
            "trace_id": self.trace_id,
            "demo_only": True,
            "notice": (
                "Educational request trace. It is returned only to this authenticated browser "
                "response and is not persisted as a production transcript. Credentials are redacted."
            ),
            "model": self.model,
            "started_at": self.started_at,
            "finished_at": _utc_now(),
            "duration_ms": round((perf_counter() - self._started) * 1000),
            "user_message": self.user_message,
            "summary": summary,
            "usage": self._usage,
            "events": self._events,
            "tool_catalogs": list(self._catalogs.values()),
            "model_turns": self._model_turns,
            "runner_calls": self._tool_calls,
        }


class DemoRunHooks(RunHooks):
    def __init__(self, recorder: DemoTraceRecorder) -> None:
        self.recorder = recorder

    async def on_llm_start(self, context, agent, system_prompt, input_items) -> None:
        self.recorder.model_turn_started(
            system_prompt=system_prompt,
            input_items=input_items,
        )

    async def on_llm_end(self, context, agent, response) -> None:
        self.recorder.model_turn_finished(response, context.usage)
