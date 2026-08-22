from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from contextlib import suppress
import json
import logging
from pathlib import Path
import re
from uuid import UUID, uuid4

from fastapi import Cookie, Depends, FastAPI, Header, HTTPException, Request, Response, status
from fastapi.responses import FileResponse, StreamingResponse
from fastapi.staticfiles import StaticFiles

from .auth import auth_service
from .config import settings
from .database import database
from .models import ChatRequest, ChatResponse, LoginRequest, LoginResponse, PrincipalContext
from .services.agent_service import customer_service_agent
from .services.writeback_service import writeback_service

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(_: FastAPI):
    await database.connect()
    yield
    await database.close()


app = FastAPI(title="Luna Telecom Customer Care", version="1.0.0", lifespan=lifespan)
static_dir = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=static_dir), name="static")


def _chat_session_id(value: str | None) -> str:
    if not value:
        return str(uuid4())
    try:
        return str(UUID(value))
    except ValueError as exc:
        raise HTTPException(status_code=422, detail="chat_session_id must be a UUID") from exc


def current_principal(
    telecom_access_token: str | None = Cookie(default=None),
    authorization: str | None = Header(default=None),
) -> PrincipalContext:
    token = telecom_access_token
    if not token and authorization and authorization.startswith("Bearer "):
        token = authorization[7:]
    if not token:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Bearer token required",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return auth_service.decode(token)


@app.get("/")
async def index():
    return FileResponse(static_dir / "index.html")


@app.get("/healthz")
async def healthz():
    return {"ok": True, "model": settings.openai_model}


@app.get("/.well-known/jwks.json")
async def jwks():
    return auth_service.jwks()


@app.post("/api/login", response_model=LoginResponse)
async def login(payload: LoginRequest, response: Response):
    rows = await database.authenticate(payload.email, payload.password, payload.account_number)
    if not rows:
        raise HTTPException(status_code=401, detail="Invalid credentials or account selection")
    if len(rows) > 1 and not payload.account_number:
        raise HTTPException(
            status_code=409,
            detail={
                "message": "Choose an account_number",
                "accounts": [
                    {"account_number": row["account_number"], "account_name": row["account_name"]}
                    for row in rows
                ],
            },
        )
    token, login_response = auth_service.issue(rows[0])
    response.set_cookie(
        key="telecom_access_token",
        value=token,
        max_age=login_response.expires_in,
        httponly=True,
        secure=settings.cookie_secure,
        samesite="strict",
        path="/",
    )
    response.headers["Cache-Control"] = "no-store"
    return login_response


@app.post("/api/logout", status_code=204)
async def logout(response: Response):
    response.delete_cookie(
        "telecom_access_token", path="/", httponly=True,
        secure=settings.cookie_secure, samesite="strict"
    )


@app.get("/api/me")
async def me(principal: PrincipalContext = Depends(current_principal)):
    return principal.model_dump(exclude={"raw_token"})


@app.get("/api/proposals/{proposal_id}")
async def proposal_status(
    proposal_id: str,
    principal: PrincipalContext = Depends(current_principal),
):
    if not re.fullmatch(r"wrp_[A-Za-z0-9_-]{8,80}", proposal_id):
        raise HTTPException(status_code=404, detail="Proposal not found")
    result = await database.proposal_status(
        proposal_id,
        principal.tenant_id,
        principal.principal_id,
    )
    if result is None:
        raise HTTPException(status_code=404, detail="Proposal not found")
    return result


@app.post("/api/chat", response_model=ChatResponse)
async def chat(payload: ChatRequest, principal: PrincipalContext = Depends(current_principal)):
    chat_session_id = _chat_session_id(payload.chat_session_id)
    await database.save_message(
        principal.tenant_id, principal.principal_id, chat_session_id, "user", payload.message
    )
    try:
        agent_response = await customer_service_agent.respond(
            principal, chat_session_id, payload.message
        )
    except Exception as exc:
        logger.exception("customer-service agent request failed")
        raise HTTPException(
            status_code=502,
            detail="The customer-service agent could not complete this request",
        ) from exc
    await database.save_message(
        principal.tenant_id,
        principal.principal_id,
        chat_session_id,
        "assistant",
        agent_response.answer,
    )
    return ChatResponse(
        chat_session_id=chat_session_id,
        answer=agent_response.answer,
        model=settings.openai_model,
        runner_trace=agent_response.trace,
    )


@app.post("/api/chat/stream")
async def chat_stream(
    payload: ChatRequest,
    principal: PrincipalContext = Depends(current_principal),
):
    """Stream the ephemeral demo trace as NDJSON while the agent is running."""
    chat_session_id = _chat_session_id(payload.chat_session_id)
    await database.save_message(
        principal.tenant_id, principal.principal_id, chat_session_id, "user", payload.message
    )
    queue: asyncio.Queue[dict] = asyncio.Queue()

    def publish_trace(event: dict) -> None:
        queue.put_nowait({"type": "trace_event", "event": event})

    async def run_agent() -> None:
        try:
            agent_response = await customer_service_agent.respond(
                principal,
                chat_session_id,
                payload.message,
                event_sink=publish_trace,
            )
            await database.save_message(
                principal.tenant_id,
                principal.principal_id,
                chat_session_id,
                "assistant",
                agent_response.answer,
            )
            stream_trace = dict(agent_response.trace)
            stream_trace["events"] = []
            response = ChatResponse(
                chat_session_id=chat_session_id,
                answer=agent_response.answer,
                model=settings.openai_model,
                runner_trace=stream_trace,
            )
            queue.put_nowait(
                {"type": "complete", "data": response.model_dump(mode="json")}
            )
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("streaming customer-service agent request failed")
            queue.put_nowait(
                {
                    "type": "error",
                    "message": "The customer-service agent could not complete this request",
                }
            )

    task = asyncio.create_task(run_agent())

    async def ndjson_stream():
        try:
            yield json.dumps(
                {"type": "session", "chat_session_id": chat_session_id},
                separators=(",", ":"),
            ) + "\n"
            while True:
                item = await queue.get()
                yield json.dumps(item, separators=(",", ":"), ensure_ascii=False) + "\n"
                if item["type"] in {"complete", "error"}:
                    break
        finally:
            if not task.done():
                task.cancel()
            with suppress(asyncio.CancelledError):
                await task

    return StreamingResponse(
        ndjson_stream(),
        media_type="application/x-ndjson",
        headers={"Cache-Control": "no-store", "X-Accel-Buffering": "no"},
    )


@app.post("/internal/synapsor/writeback")
async def synapsor_writeback(request: Request):
    return await writeback_service.handle(request)
