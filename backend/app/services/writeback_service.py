from __future__ import annotations

import hashlib
import hmac
import json
import logging
from dataclasses import dataclass
from datetime import datetime, timezone
from typing import Any
from uuid import UUID, uuid4

from fastapi import HTTPException, Request

from ..config import settings
from ..database import database

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class ActionRule:
    table: str
    primary_key: str
    allowed_patch: frozenset[str]
    authorization: str


ACTION_RULES = {
    "account.propose_plan_change": ActionRule(
        table="subscriptions",
        primary_key="subscription_id",
        allowed_patch=frozenset({"plan_code", "base_monthly_cents"}),
        authorization="manage_account",
    ),
    "line.propose_roaming_change": ActionRule(
        table="service_lines",
        primary_key="line_id",
        allowed_patch=frozenset({"international_roaming_enabled"}),
        authorization="view_line",
    ),
    "billing.propose_autopay_change": ActionRule(
        table="billing_preferences",
        primary_key="billing_preference_id",
        allowed_patch=frozenset({"autopay_enabled"}),
        authorization="manage_account",
    ),
    "billing.propose_paperless_change": ActionRule(
        table="billing_preferences",
        primary_key="billing_preference_id",
        allowed_patch=frozenset({"paperless_billing"}),
        authorization="manage_account",
    ),
    "billing.propose_spend_alert_change": ActionRule(
        table="billing_preferences",
        primary_key="billing_preference_id",
        allowed_patch=frozenset({"monthly_spend_alert_cents"}),
        authorization="manage_account",
    ),
    "support.propose_case_note": ActionRule(
        table="support_cases",
        primary_key="case_id",
        allowed_patch=frozenset({"latest_customer_note", "note_policy_units"}),
        authorization="view_support_case",
    ),
}

PLAN_VALUES = {
    "starter": {
        "plan_display_name": "Starter 15 GB",
        "base_monthly_cents": 4500,
        "included_lines": 1,
        "data_policy": "15 GB high-speed data",
        "international_day_pass": False,
    },
    "unlimited": {
        "plan_display_name": "Unlimited",
        "base_monthly_cents": 6500,
        "included_lines": 1,
        "data_policy": "Unlimited data; speeds may slow after 75 GB",
        "international_day_pass": False,
    },
    "unlimited_plus": {
        "plan_display_name": "Unlimited Plus",
        "base_monthly_cents": 13500,
        "included_lines": 3,
        "data_policy": "Unlimited data; 30 GB hotspot per line",
        "international_day_pass": False,
    },
    "family_premium": {
        "plan_display_name": "Family Premium",
        "base_monthly_cents": 16500,
        "included_lines": 4,
        "data_policy": "Unlimited premium data; 60 GB hotspot per line",
        "international_day_pass": True,
    },
}


def _safe_receipt(
    status: str,
    code: str | None = None,
    *,
    previous_version: Any = None,
    new_version: Any = None,
    rows: int = 0,
    mutated: bool = False,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "status": status,
        "rows_affected": rows,
        "source_database_mutated": mutated,
    }
    if code:
        result["safe_error_code"] = code
    if previous_version is not None:
        result["previous_version"] = previous_version
    if new_version is not None:
        result["new_version"] = new_version
    return result


def _verify_request(request: Request, raw_body: bytes) -> None:
    if request.headers.get("authorization") != f"Bearer {settings.handler_token}":
        raise HTTPException(status_code=401, detail="UNAUTHORIZED")
    issued_text = request.headers.get("x-synapsor-issued-at", "")
    signature = request.headers.get("x-synapsor-signature", "")
    try:
        issued_at = datetime.fromisoformat(issued_text.replace("Z", "+00:00"))
    except ValueError as exc:
        raise HTTPException(status_code=401, detail="INVALID_HANDLER_TIMESTAMP") from exc
    skew = abs((datetime.now(timezone.utc) - issued_at).total_seconds())
    if skew > 300:
        raise HTTPException(status_code=401, detail="STALE_HANDLER_REQUEST")
    expected = "sha256=" + hmac.new(
        settings.handler_signing_secret.encode(), raw_body, hashlib.sha256
    ).hexdigest()
    if not hmac.compare_digest(signature, expected):
        raise HTTPException(status_code=401, detail="INVALID_HANDLER_SIGNATURE")


class WritebackService:
    async def handle(self, request: Request) -> dict[str, Any]:
        raw_body = await request.body()
        _verify_request(request, raw_body)
        try:
            payload = json.loads(raw_body)
            proposal_id = str(payload["proposal_id"])
            idempotency_key = str(payload["idempotency_key"])
            change_set = payload.get("change_set")
            if change_set is not None:
                action = str(change_set["action"])
                target = change_set["target"]
                patch = change_set["patch"]
                guards = change_set["guards"]
                tenant_id = str(change_set["scope"]["tenant_id"])
                object_id = str(change_set["scope"]["object_id"])
            else:
                action = str(payload["action"])
                target = payload["target"]
                patch = payload["patch"]
                guards = payload["guards"]
                tenant_id = str(payload["tenant_guard"]["value"])
                object_id = str(target["primary_key"]["value"])
            ledger_scope = await database.proposal_scope(proposal_id)
            if ledger_scope is None or ledger_scope[0] != tenant_id:
                raise ValueError("proposal scope missing or inconsistent")
            principal_id = ledger_scope[1]
            UUID(tenant_id)
            UUID(object_id)
            UUID(principal_id)
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
            raise HTTPException(status_code=400, detail="BAD_WRITEBACK_REQUEST") from exc

        prior = await database.prior_receipt(idempotency_key)
        if prior:
            response = dict(prior["response"])
            response["status"] = "already_applied"
            return response
        if payload.get("dry_run"):
            return _safe_receipt("applied", rows=0, mutated=False)

        rule = ACTION_RULES.get(action)
        if (
            rule is None
            or target.get("schema") != "telecom"
            or target.get("table") != rule.table
            or target.get("primary_key", {}).get("column") != rule.primary_key
            or str(target.get("primary_key", {}).get("value")) != object_id
            or set(patch) != set(rule.allowed_patch)
            or guards.get("tenant", {}).get("column") != "account_id"
            or str(guards.get("tenant", {}).get("value")) != tenant_id
            or guards.get("expected_version", {}).get("column") != "version"
        ):
            return _safe_receipt("failed", "ACTION_NOT_ALLOWLISTED")

        assert database.write_pool is not None
        try:
            async with database.scoped_transaction(
                database.write_pool, tenant_id, principal_id
            ) as connection:
                if rule.authorization == "manage_account":
                    allowed = await connection.fetchval(
                        "SELECT telecom.can_manage_account($1::uuid, $2::uuid)",
                        tenant_id,
                        principal_id,
                    )
                elif rule.authorization == "view_line":
                    allowed = await connection.fetchval(
                        "SELECT telecom.can_view_line($1::uuid, $2::uuid, $3::uuid)",
                        tenant_id,
                        object_id,
                        principal_id,
                    )
                elif rule.authorization == "view_support_case":
                    allowed = await connection.fetchval(
                        "SELECT telecom.can_view_support_case($1::uuid, $2::uuid, $3::uuid)",
                        tenant_id,
                        object_id,
                        principal_id,
                    )
                else:
                    raise ValueError("unknown action authorization")
                if not allowed:
                    return _safe_receipt("conflict", "ROW_NOT_FOUND_OR_WRONG_SCOPE")

                query = (
                    f'SELECT * FROM telecom."{rule.table}" '
                    f'WHERE "{rule.primary_key}" = $1::uuid AND account_id = $2::uuid FOR UPDATE'
                )
                row = await connection.fetchrow(query, object_id, tenant_id)
                if row is None:
                    return _safe_receipt("conflict", "ROW_NOT_FOUND_OR_WRONG_SCOPE")

                expected_version = str(guards["expected_version"]["value"])
                previous_version = str(row["version"])
                if previous_version != expected_version:
                    return _safe_receipt(
                        "conflict",
                        "ROW_CHANGED_AFTER_PROPOSAL",
                        previous_version=previous_version,
                    )

                if action == "support.propose_case_note":
                    return await self._apply_case_note(
                        connection=connection,
                        row=dict(row),
                        patch=patch,
                        tenant_id=tenant_id,
                        principal_id=principal_id,
                        object_id=object_id,
                        proposal_id=proposal_id,
                        idempotency_key=idempotency_key,
                        previous_version=previous_version,
                    )

                old_values, new_values = self._business_values(action, patch, dict(row))
                new_version = int(row["version"]) + 1
                assignments = list(new_values)
                set_sql = ", ".join(
                    [f'"{column}" = ${index + 1}' for index, column in enumerate(assignments)]
                    + [f'updated_at = ${len(assignments) + 1}', f'version = ${len(assignments) + 2}']
                )
                params = [new_values[column] for column in assignments]
                params.extend([datetime.now(timezone.utc), new_version, object_id, tenant_id])
                update_sql = (
                    f'UPDATE telecom."{rule.table}" SET {set_sql} '
                    f'WHERE "{rule.primary_key}" = ${len(assignments) + 3}::uuid '
                    f'AND account_id = ${len(assignments) + 4}::uuid RETURNING version'
                )
                updated = await connection.fetchrow(update_sql, *params)
                if updated is None:
                    return _safe_receipt("conflict", "ROW_NOT_FOUND_OR_WRONG_SCOPE")

                if action == "account.propose_plan_change":
                    await connection.execute(
                        "SELECT telecom.sync_subscription_projection($1::uuid, $2::uuid)",
                        tenant_id, object_id,
                    )
                elif action == "line.propose_roaming_change":
                    await connection.execute(
                        "SELECT telecom.sync_line_projection($1::uuid, $2::uuid)",
                        tenant_id, object_id,
                    )
                else:
                    await connection.execute(
                        "SELECT telecom.sync_billing_projection($1::uuid, $2::uuid)",
                        tenant_id, object_id,
                    )

                await connection.execute(
                    """
                    INSERT INTO telecom.plan_change_events
                      (change_event_id, account_id, principal_id, proposal_id, action_name,
                       target_table, target_id, old_values, new_values)
                    VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5, $6, $7::uuid, $8::jsonb, $9::jsonb)
                    """,
                    str(uuid4()), tenant_id, principal_id, proposal_id, action,
                    rule.table, object_id, json.dumps(old_values, default=str),
                    json.dumps(new_values, default=str),
                )
                response = _safe_receipt(
                    "applied",
                    previous_version=previous_version,
                    new_version=str(updated["version"]),
                    rows=1,
                    mutated=True,
                )
                await database.store_receipt(
                    connection, idempotency_key, proposal_id, tenant_id, response
                )
                return response
        except Exception:
            logger.exception("guarded writeback failed for action %s", action)
            return _safe_receipt("failed", "SAFE_INTERNAL_WRITEBACK_FAILURE")

    async def _apply_case_note(
        self,
        *,
        connection,
        row: dict[str, Any],
        patch: dict[str, Any],
        tenant_id: str,
        principal_id: str,
        object_id: str,
        proposal_id: str,
        idempotency_key: str,
        previous_version: str,
    ) -> dict[str, Any]:
        if row["status"] == "closed":
            return _safe_receipt(
                "conflict",
                "SUPPORT_CASE_CLOSED",
                previous_version=previous_version,
            )

        note = patch.get("latest_customer_note")
        policy_units = patch.get("note_policy_units")
        if not isinstance(note, str) or note != note.strip() or not note:
            raise ValueError("case note must be non-empty and trimmed")
        if policy_units != 1 or len(note) > 1000:
            raise ValueError("case note is outside the reviewed bounded-note policy")

        now = datetime.now(timezone.utc)
        new_version = int(row["version"]) + 1
        updated = await connection.fetchrow(
            """
            UPDATE telecom.support_cases
            SET latest_customer_note = $1,
                latest_customer_note_length = $2,
                note_policy_units = 1,
                customer_note_count = customer_note_count + 1,
                updated_at = $3,
                version = $4
            WHERE case_id = $5::uuid AND account_id = $6::uuid
            RETURNING version, customer_note_count
            """,
            note,
            len(note),
            now,
            new_version,
            object_id,
            tenant_id,
        )
        if updated is None:
            return _safe_receipt("conflict", "ROW_NOT_FOUND_OR_WRONG_SCOPE")

        await connection.execute(
            """
            INSERT INTO telecom.support_case_notes
              (note_id, account_id, case_id, author_principal_id, note_kind,
               note_body, note_length, proposal_id, created_at)
            VALUES ($1::uuid, $2::uuid, $3::uuid, $4::uuid, 'customer',
                    $5, $6, $7, $8)
            """,
            str(uuid4()),
            tenant_id,
            object_id,
            principal_id,
            note,
            len(note),
            proposal_id,
            now,
        )
        await connection.execute(
            "SELECT telecom.sync_support_case_projection($1::uuid, $2::uuid)",
            tenant_id,
            object_id,
        )

        old_values = {
            "latest_customer_note_length": row["latest_customer_note_length"],
            "customer_note_count": row["customer_note_count"],
        }
        new_values = {
            "latest_customer_note_length": len(note),
            "customer_note_count": updated["customer_note_count"],
        }
        await connection.execute(
            """
            INSERT INTO telecom.plan_change_events
              (change_event_id, account_id, principal_id, proposal_id, action_name,
               target_table, target_id, old_values, new_values)
            VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5, 'support_cases',
                    $6::uuid, $7::jsonb, $8::jsonb)
            """,
            str(uuid4()),
            tenant_id,
            principal_id,
            proposal_id,
            "support.propose_case_note",
            object_id,
            json.dumps(old_values),
            json.dumps(new_values),
        )
        response = _safe_receipt(
            "applied",
            previous_version=previous_version,
            new_version=str(updated["version"]),
            rows=1,
            mutated=True,
        )
        await database.store_receipt(
            connection, idempotency_key, proposal_id, tenant_id, response
        )
        return response

    @staticmethod
    def _business_values(action: str, patch: dict[str, Any], row: dict[str, Any]):
        if action == "account.propose_plan_change":
            plan_code = str(patch["plan_code"])
            plan = PLAN_VALUES.get(plan_code)
            if plan is None:
                raise ValueError("unsupported plan")
            proposed_price = patch.get("base_monthly_cents")
            if isinstance(proposed_price, bool) or int(proposed_price) != plan["base_monthly_cents"]:
                raise ValueError("plan price does not match the reviewed catalog")
            if int(plan["included_lines"]) < 1:
                raise ValueError("invalid plan")
            old = {
                "plan_code": str(row["plan_code"]),
                "plan_display_name": row["plan_display_name"],
                "base_monthly_cents": row["base_monthly_cents"],
            }
            new = {"plan_code": plan_code, **plan, "effective_from": datetime.now(timezone.utc).date()}
            return old, new
        column = next(iter(patch))
        value = patch[column]
        if action == "billing.propose_spend_alert_change":
            if isinstance(value, bool) or not isinstance(value, (int, float)):
                raise ValueError("alert threshold must be numeric")
            value = int(value)
            if value < 1000 or value > 50000:
                raise ValueError("alert threshold outside reviewed bounds")
            return {column: row[column]}, {column: value}
        if not isinstance(value, bool):
            raise ValueError("toggle value must be boolean")
        return {column: row[column]}, {column: value}


writeback_service = WritebackService()
