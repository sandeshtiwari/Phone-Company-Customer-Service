from __future__ import annotations

import os
from dataclasses import dataclass


def required(name: str) -> str:
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Missing required environment variable: {name}")
    return value


@dataclass(frozen=True)
class Settings:
    auth_database_url: str
    app_database_url: str
    write_database_url: str
    control_database_url: str
    openai_model: str
    jwt_issuer: str
    jwt_audiences: tuple[str, ...]
    jwt_key_path: str
    explore_mcp_url: str
    actions_mcp_url: str
    handler_token: str
    handler_signing_secret: str
    cookie_secure: bool

    @classmethod
    def from_env(cls) -> "Settings":
        audiences = tuple(
            item.strip()
            for item in required("JWT_AUDIENCES").split(",")
            if item.strip()
        )
        if len(audiences) != 2:
            raise RuntimeError("JWT_AUDIENCES must contain Explore and actions audiences")
        return cls(
            auth_database_url=required("TELECOM_AUTH_DATABASE_URL"),
            app_database_url=required("TELECOM_APP_DATABASE_URL"),
            write_database_url=required("TELECOM_WRITE_DATABASE_URL"),
            control_database_url=required("TELECOM_CONTROL_DATABASE_URL"),
            openai_model=os.getenv("OPENAI_MODEL", "gpt-5.6-luna"),
            jwt_issuer=os.getenv("JWT_ISSUER", "https://telecom.local"),
            jwt_audiences=audiences,
            jwt_key_path=os.getenv("JWT_KEY_PATH", "/runtime/jwt-private.pem"),
            explore_mcp_url=required("EXPLORE_MCP_URL"),
            actions_mcp_url=required("ACTIONS_MCP_URL"),
            handler_token=required("SYNAPSOR_APP_HANDLER_TOKEN"),
            handler_signing_secret=required("SYNAPSOR_APP_HANDLER_SIGNING_SECRET"),
            cookie_secure=os.getenv("COOKIE_SECURE", "false").lower() == "true",
        )


settings = Settings.from_env()
