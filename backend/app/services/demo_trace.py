from __future__ import annotations

from dataclasses import asdict, dataclass, is_dataclass
from datetime import date, datetime, timezone
from enum import Enum
import json
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

_HIGHLIGHT_KEYS = {
    "account_name": "Account",
    "account_kind": "Account type",
    "adjustments_cents": "Adjustments",
    "amount_due": "Amount due",
    "amount_cents": "Payment amount",
    "autopay_enabled": "AutoPay",
    "base_monthly_cents": "Monthly plan price",
    "balance_cents": "Balance remaining",
    "balance_remaining": "Balance remaining",
    "billing_period_end": "Billing period end",
    "billing_period_start": "Billing period start",
    "case_number": "Case",
    "category": "Category",
    "customer_note_count": "Customer notes",
    "data_limit_gb": "Data limit (GB)",
    "data_mb": "Data used (MB)",
    "data_used_gb": "Data used (GB)",
    "device_name": "Device",
    "display_name": "Member",
    "due_date": "Due date",
    "invoice_number": "Invoice",
    "included_lines": "Included lines",
    "international_day_pass": "International day pass",
    "international_roaming_enabled": "International roaming",
    "latest_customer_note": "Latest customer note",
    "latest_update_summary": "Latest update",
    "new_value": "New value",
    "note_text": "Note",
    "line_label": "Line",
    "monthly_spend_alert_cents": "Monthly spend alert",
    "paperless_billing": "Paperless billing",
    "period_end": "Billing period end",
    "period_start": "Billing period start",
    "phone_last4": "Phone ending",
    "plan_code": "Plan code",
    "plan_display_name": "Plan",
    "plan_name": "Plan",
    "previous_value": "Previous value",
    "priority": "Priority",
    "proposal_id": "Proposal",
    "relationship_label": "Relationship",
    "roaming_data_mb": "Roaming data (MB)",
    "sms_count": "Messages",
    "source_database_changed": "Database changed",
    "status": "Status",
    "subject": "Subject",
    "subtotal_cents": "Subtotal",
    "taxes_cents": "Taxes",
    "total_cents": "Invoice total",
    "total_amount": "Invoice total",
    "usage_date": "Usage date",
    "usage_month": "Usage month",
    "voice_minutes": "Voice minutes",
}

_VALIDATION_KEYS = {
    "approval_status": "Approval status",
    "boundary_digest": "Boundary digest",
    "decision": "Decision",
    "error_code": "Error code",
    "evidence_handle": "Evidence handle",
    "evidence_id": "Evidence ID",
    "plan_fingerprint": "Plan fingerprint",
    "proposal_id": "Proposal ID",
    "query_audit_id": "Query audit ID",
    "query_id": "Query ID",
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


def _decode_runner_payload(response: Any) -> Any:
    """Prefer Runner's JSON body while retaining the unmodified MCP response elsewhere."""
    if not isinstance(response, dict):
        return response
    structured = response.get("structured_content") or response.get("structuredContent")
    if structured:
        return structured
    for item in response.get("content") or []:
        if not isinstance(item, dict) or not isinstance(item.get("text"), str):
            continue
        try:
            return json.loads(item["text"])
        except json.JSONDecodeError:
            continue
    return response


def _expand_embedded_json(value: Any, *, depth: int = 0) -> Any:
    """Make JSON encoded inside MCP text fields readable in the demo inspector."""
    if depth >= 10:
        return value
    if isinstance(value, str):
        candidate = value.strip()
        if not candidate.startswith(("{", "[")):
            return value
        try:
            decoded = json.loads(candidate)
        except json.JSONDecodeError:
            return value
        return _expand_embedded_json(decoded, depth=depth + 1)
    if isinstance(value, dict):
        return {
            key: _expand_embedded_json(child, depth=depth + 1)
            for key, child in value.items()
        }
    if isinstance(value, list):
        return [_expand_embedded_json(child, depth=depth + 1) for child in value]
    return value


def _walk_scalars(value: Any, path: tuple[str, ...] = ()):
    if isinstance(value, dict):
        for key, child in value.items():
            yield from _walk_scalars(child, (*path, str(key)))
    elif isinstance(value, list):
        for index, child in enumerate(value):
            yield from _walk_scalars(child, (*path, str(index + 1)))
    elif value is None or isinstance(value, (str, int, float, bool)):
        yield path, value


def _read_outcome(decoded: Any) -> tuple[Any, Any, Any]:
    if not isinstance(decoded, dict):
        return None, None, None
    ok = decoded.get("ok")
    outcome = decoded.get("outcome")
    outcome_type = outcome.get("type") if isinstance(outcome, dict) else None
    status = decoded.get("status")
    if isinstance(outcome, dict):
        status = status or outcome.get("status")
        result = outcome.get("result")
        if isinstance(result, dict):
            status = status or result.get("status")
    return ok, outcome_type, status


def _extract_highlights(decoded: Any, *, maximum: int = 14) -> list[dict[str, Any]]:
    highlights: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()
    for path, value in _walk_scalars(decoded):
        if not path or path[-1] not in _HIGHLIGHT_KEYS or value in (None, ""):
            continue
        key = path[-1]
        if key == "status" and str(value).lower() in {"ok", "success"}:
            continue
        identity = (key, str(value))
        if identity in seen:
            continue
        seen.add(identity)
        label = _HIGHLIGHT_KEYS[key]
        numeric_parent = next((part for part in reversed(path[:-1]) if part.isdigit()), None)
        if numeric_parent:
            label = f"Row {numeric_parent} · {label}"
        display_value = value
        if key.endswith("_cents") and isinstance(value, (int, float)) and not isinstance(value, bool):
            display_value = f"${value / 100:,.2f}"
        highlights.append(
            {"label": label, "value": display_value, "path": ".".join(path)}
        )
        if len(highlights) >= maximum:
            break
    return highlights


def _validation_summary(
    *,
    response: Any,
    model_tool_name: str,
    runner_tool_name: str,
    status: str,
) -> dict[str, Any]:
    decoded = _decode_runner_payload(response)
    ok, outcome_type, runner_status = _read_outcome(decoded)
    rejected = status == "error" or ok is False or outcome_type in {"error", "refusal", "refused"}
    details: list[dict[str, Any]] = []
    seen: set[tuple[str, str]] = set()
    for path, value in _walk_scalars(decoded):
        if not path or path[-1] not in _VALIDATION_KEYS or value in (None, ""):
            continue
        identity = (path[-1], str(value))
        if identity in seen:
            continue
        seen.add(identity)
        details.append(
            {
                "label": _VALIDATION_KEYS[path[-1]],
                "value": value,
                "path": ".".join(path),
            }
        )
        if len(details) >= 8:
            break
    return {
        "decision": "rejected" if rejected else "accepted",
        "transport_status": status,
        "runner_reported": {
            "ok": ok,
            "outcome": outcome_type,
            "status": runner_status,
        },
        "tool": {
            "model_name": model_tool_name,
            "canonical_runner_name": runner_tool_name,
            "alias_translated": model_tool_name != runner_tool_name,
        },
        "reported_checks": details,
        "explanation": (
            "This validation view is derived from Runner's MCP result metadata. "
            "It does not invent internal checks that Runner did not report."
        ),
    }


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
            kind="model.context",
            stage="model",
            title="What the model sees",
            payload={
                "turn": turn["turn"],
                "instructions": system_prompt,
                "conversation_input": _expand_embedded_json(turn["input_items"]),
                "available_runner_tools": list(self._catalogs.values()),
            },
        )

    def model_turn_finished(self, response: Any, usage: Any) -> None:
        if self._model_turns:
            self._model_turns[-1]["model_output"] = safe_json(response)
            self._model_turns[-1]["finished_at"] = _utc_now()
        self._usage = safe_json(usage)

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
            kind="model.request",
            stage="request",
            title="What the model sends",
            payload={
                "call_id": call_id,
                "server": server,
                "model_emitted": event["model_emitted"],
                "runner_alias_translation": {
                    "canonical_name": runner_tool_name,
                    "translated": model_tool_name != runner_tool_name,
                },
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
        validation = _validation_summary(
            response=open_call.event["runner_response"],
            model_tool_name=open_call.event["model_emitted"]["name"],
            runner_tool_name=open_call.event["runner_request"]["name"],
            status="ok",
        )
        highlights = (
            []
            if open_call.event["runner_request"]["name"] == "app.describe_data"
            else _extract_highlights(_decode_runner_payload(open_call.event["runner_response"]))
        )
        open_call.event["validation"] = validation
        open_call.event["highlights"] = highlights
        self._emit(
            kind="runner.validation",
            stage="validation",
            title="Runner validation",
            payload={
                "call_id": call_id,
                "duration_ms": open_call.event["duration_ms"],
                "validation": validation,
            },
        )
        self._emit(
            kind="runner.response",
            stage="response",
            title="Decoded Runner response",
            payload={
                "call_id": call_id,
                "tool": open_call.event["runner_request"]["name"],
                "status": "ok",
                "duration_ms": open_call.event["duration_ms"],
                "highlights": highlights,
                "response_format": "decoded Runner JSON body",
                "response": _expand_embedded_json(
                    _decode_runner_payload(open_call.event["runner_response"])
                ),
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
        validation = _validation_summary(
            response=open_call.event["runner_response"],
            model_tool_name=open_call.event["model_emitted"]["name"],
            runner_tool_name=open_call.event["runner_request"]["name"],
            status="error",
        )
        open_call.event["validation"] = validation
        open_call.event["highlights"] = []
        self._emit(
            kind="runner.validation",
            stage="validation",
            title="Runner validation",
            payload={
                "call_id": call_id,
                "duration_ms": open_call.event["duration_ms"],
                "validation": validation,
            },
        )
        self._emit(
            kind="runner.response",
            stage="response",
            title="Decoded Runner response",
            payload={
                "call_id": call_id,
                "tool": open_call.event["runner_request"]["name"],
                "status": "error",
                "duration_ms": open_call.event["duration_ms"],
                "highlights": [],
                "response_format": "decoded Runner error",
                "response": _expand_embedded_json(
                    _decode_runner_payload(open_call.event["runner_response"])
                ),
            },
        )

    def finish(self) -> dict[str, Any]:
        summary = {
            "model_turns": len(self._model_turns),
            "runner_calls": len(self._tool_calls),
            "successful_calls": sum(call["status"] == "ok" for call in self._tool_calls),
            "failed_calls": sum(call["status"] == "error" for call in self._tool_calls),
        }
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
