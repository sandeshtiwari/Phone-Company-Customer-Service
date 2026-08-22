from __future__ import annotations

import json
from contextlib import asynccontextmanager
from typing import AsyncIterator

import asyncpg

from .config import settings


class Database:
    auth_pool: asyncpg.Pool | None = None
    app_pool: asyncpg.Pool | None = None
    write_pool: asyncpg.Pool | None = None
    control_pool: asyncpg.Pool | None = None

    async def connect(self) -> None:
        self.auth_pool = await asyncpg.create_pool(settings.auth_database_url, min_size=1, max_size=5)
        self.app_pool = await asyncpg.create_pool(settings.app_database_url, min_size=1, max_size=10)
        self.write_pool = await asyncpg.create_pool(settings.write_database_url, min_size=1, max_size=5)
        self.control_pool = await asyncpg.create_pool(settings.control_database_url, min_size=1, max_size=3)

    async def close(self) -> None:
        for pool in (self.auth_pool, self.app_pool, self.write_pool, self.control_pool):
            if pool is not None:
                await pool.close()

    async def authenticate(self, email: str, password: str, account_number: str | None):
        assert self.auth_pool is not None
        rows = await self.auth_pool.fetch(
            "SELECT * FROM telecom.authenticate_principal($1, $2)", email, password
        )
        if account_number:
            rows = [row for row in rows if row["account_number"] == account_number]
        return rows

    @asynccontextmanager
    async def scoped_transaction(
        self, pool: asyncpg.Pool, tenant_id: str, principal_id: str
    ) -> AsyncIterator[asyncpg.Connection]:
        async with pool.acquire() as connection:
            async with connection.transaction():
                await connection.execute(
                    "SELECT set_config('synapsor.tenant_id', $1, true), "
                    "set_config('synapsor.principal', $2, true)",
                    tenant_id,
                    principal_id,
                )
                yield connection

    async def save_message(
        self,
        tenant_id: str,
        principal_id: str,
        chat_session_id: str,
        role: str,
        content: str,
    ) -> None:
        assert self.app_pool is not None
        async with self.scoped_transaction(self.app_pool, tenant_id, principal_id) as connection:
            await connection.execute(
                """
                INSERT INTO telecom.chat_sessions
                  (chat_session_id, account_id, principal_id)
                VALUES ($1::uuid, $2::uuid, $3::uuid)
                ON CONFLICT (chat_session_id) DO UPDATE SET updated_at = now()
                """,
                chat_session_id,
                tenant_id,
                principal_id,
            )
            await connection.execute(
                """
                INSERT INTO telecom.chat_messages
                  (account_id, chat_session_id, principal_id, message_role, content)
                VALUES ($1::uuid, $2::uuid, $3::uuid, $4, $5)
                """,
                tenant_id,
                chat_session_id,
                principal_id,
                role,
                content,
            )

    async def prior_receipt(self, idempotency_key: str):
        assert self.write_pool is not None
        async with self.write_pool.acquire() as connection:
            return await connection.fetchrow(
                "SELECT response FROM synapsor_app.handler_receipts WHERE idempotency_key = $1",
                idempotency_key,
            )

    async def proposal_scope(self, proposal_id: str) -> tuple[str, str] | None:
        assert self.control_pool is not None
        async with self.control_pool.acquire() as connection:
            row = await connection.fetchrow(
                """
                SELECT tenant_id, payload_json ->> 'principal' AS principal
                FROM synapsor_actions.ledger_entries
                WHERE kind = 'proposal' AND proposal_id = $1
                ORDER BY entry_id DESC
                LIMIT 1
                """,
                proposal_id,
            )
        if not row or not row["tenant_id"] or not row["principal"]:
            return None
        return str(row["tenant_id"]), str(row["principal"])

    async def proposal_status(
        self,
        proposal_id: str,
        tenant_id: str,
        principal_id: str,
    ) -> dict | None:
        """Return a safe status only when the proposal belongs to this session scope."""
        assert self.control_pool is not None
        async with self.control_pool.acquire() as connection:
            proposal = await connection.fetchrow(
                """
                SELECT capability,
                       payload_json ->> 'state' AS state,
                       payload_json ->> 'updated_at' AS updated_at,
                       COALESCE(
                         (payload_json ->> 'source_database_mutated')::boolean,
                         false
                       ) AS source_database_mutated
                FROM synapsor_actions.ledger_entries
                WHERE kind = 'proposal'
                  AND proposal_id = $1
                  AND tenant_id = $2
                  AND payload_json ->> 'principal' = $3
                ORDER BY entry_id DESC
                LIMIT 1
                """,
                proposal_id,
                tenant_id,
                principal_id,
            )
            if not proposal:
                return None
            receipt = await connection.fetchrow(
                """
                SELECT payload_json -> 'receipt' AS receipt
                FROM synapsor_actions.ledger_entries
                WHERE kind = 'writeback_receipt' AND proposal_id = $1
                ORDER BY entry_id DESC
                LIMIT 1
                """,
                proposal_id,
            )
        safe_receipt = None
        if receipt and receipt["receipt"]:
            raw_value = receipt["receipt"]
            raw_receipt = json.loads(raw_value) if isinstance(raw_value, str) else dict(raw_value)
            safe_receipt = {
                key: raw_receipt.get(key)
                for key in (
                    "status",
                    "rows_affected",
                    "previous_version",
                    "new_version",
                    "executed_at",
                    "source_database_mutated",
                )
            }
        return {
            "proposal_id": proposal_id,
            "capability": proposal["capability"],
            "status": proposal["state"] or "unknown",
            "source_database_changed": bool(proposal["source_database_mutated"]),
            "updated_at": proposal["updated_at"],
            "receipt": safe_receipt,
        }

    async def store_receipt(
        self,
        connection: asyncpg.Connection,
        idempotency_key: str,
        proposal_id: str,
        tenant_id: str,
        response: dict,
    ) -> None:
        await connection.execute(
            """
            INSERT INTO synapsor_app.handler_receipts
              (idempotency_key, proposal_id, account_id, status, previous_version, new_version, response)
            VALUES ($1, $2, $3::uuid, $4, $5, $6, $7::jsonb)
            """,
            idempotency_key,
            proposal_id,
            tenant_id,
            response["status"],
            str(response.get("previous_version", "")),
            str(response.get("new_version", "")),
            json.dumps(response),
        )


database = Database()
