from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


class LoginRequest(BaseModel):
    email: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=8, max_length=128)
    account_number: str | None = Field(default=None, max_length=32)


class AccountChoice(BaseModel):
    account_id: str
    account_number: str
    account_name: str
    membership_role: str


class LoginResponse(BaseModel):
    expires_in: int
    principal_id: str
    display_name: str
    account: AccountChoice


class ChatRequest(BaseModel):
    message: str = Field(min_length=1, max_length=4000)
    chat_session_id: str | None = None


class ChatResponse(BaseModel):
    chat_session_id: str
    answer: str
    model: str
    runner_trace: dict[str, Any]


class PrincipalContext(BaseModel):
    principal_id: str
    tenant_id: str
    display_name: str
    account_name: str
    membership_role: str
    raw_token: str
