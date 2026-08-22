# Luna Telecom × Synapsor Runner

A complete, Dockerized demonstration of a multi-tenant telecom customer-service chatbot. It combines PostgreSQL 16, Synapsor Runner production Explore and reviewed write proposals, the OpenAI Agents SDK, JWT-scoped customer access, and a browser UI that visualizes model → Runner → model calls in real time.

## Quick start

### Requirements

- Docker Engine with Docker Compose v2
- An OpenAI API key
- Git
- Free local ports `8080`, `5544`, `8766`, and `8767`

### 1. Clone and configure

```bash
git clone https://github.com/YOUR_USERNAME/YOUR_REPOSITORY.git
cd YOUR_REPOSITORY
cp .env.example .env
```

Open `.env` and set the only required value:

```dotenv
OPENAI_API_KEY=your-openai-api-key
```

The default model is `gpt-5.6-luna`. Change `OPENAI_MODEL` in `.env` if needed.

### 2. Run the complete application

```bash
./scripts/start.sh
```

That one command builds and starts PostgreSQL, the FastAPI app, both Synapsor MCP servers, the shared control store, and the trusted proposal auto-applier. It also handles the required first-boot ordering for Runner's JWT verification key.

Open [http://127.0.0.1:8080](http://127.0.0.1:8080). To verify the stack from a terminal:

```bash
curl --fail http://127.0.0.1:8080/healthz
docker compose --env-file .env ps
```

The same `./scripts/start.sh` command can be used after a reboot. PostgreSQL data is retained in a Docker volume.

### Manual Docker startup

If you do not want to use the helper script, run these commands from the repository root:

```bash
mkdir -p .runtime
docker compose --env-file .env up -d --build postgres schema-migrate control-store-init backend
until [ -f .runtime/jwt-public.pem ]; do sleep 1; done
docker compose --env-file .env up -d --build runner-explore runner-actions runner-auto-apply
```

The two phases matter on a clean checkout: the backend creates the RSA keypair first, and Runner receives only the public key.

### Rebuild the reviewed action contract

The model-facing inspection and write-proposal contracts are authored in `synapsor/actions/telecom-actions.synapsor.sql`. The generated canonical contract is `synapsor/actions/telecom-actions.contract.json`; `synapsor.runner.json` references that artifact and contains only deployment wiring such as sources, JWT verification, storage, HTTP security, and the app-handler connection.

`./scripts/start.sh` compiles and validates the contract automatically. To rebuild it without starting the application, run from the repository root:

```bash
./scripts/compile-actions.sh
```

If `synapsor-runner` is installed globally, the script uses it. Otherwise, it builds and uses the pinned project Docker image. Do not hand-edit `telecom-actions.contract.json`; edit the DSL and compile it again.

### Stop without deleting data

```bash
docker compose --env-file .env down
```

Do not add `--volumes` unless you intentionally want to erase and reseed the database.

## Demo logins

All demo users have password `demo123!`.

| Access | Email | Account number | Expected scope |
| --- | --- | --- | --- |
| Family owner | `alex.atlas@example.test` | `US-100001` | All four Atlas subscribers and lines; account billing |
| Family member | `maya.atlas@example.test` | `US-100001` | Maya's subscriber, line, and usage only; no household billing |
| Individual owner | `eli.chen@example.test` | `US-100003` | Eli's account only |

Try asking:

```text
Who is on my family plan, and what plan do we have?
What is our usage based on members in my account?
How much mobile data did each visible line use over the last 30 days?
What is my latest invoice balance?
What is the status of my support issues?
Add this note to my open eSIM case: The download is still pending after another restart.
Change my plan to Unlimited Plus at $135 per month.
Set my monthly spend alert to $150.
```

## Architecture

```text
Browser
  -> FastAPI login/chat API (signed HttpOnly JWT cookie)
      -> OpenAI Agents SDK / gpt-5.6-luna
          -> production Explore HTTP: app.describe_data + app.explore_data
          -> reviewed action HTTP: inspect + proposal tools
      -> app-owned guarded writeback handler
          -> PostgreSQL base tables + customer-scoped Explore read model
```

- One telecom account is one tenant. Principals can belong to one or more accounts.
- Family owners/managers receive reviewed household rows. Members receive only their own subscriber, line, and usage rows. Individual owners receive only their own account.
- Runner binds mandatory tenant and principal scope from verified JWT claims; neither value is supplied by the model.
- PostgreSQL row-level security remains active for application and action reads/writes.
- Production Explore exposes exactly `app.describe_data` and `app.explore_data`.
- OpenAI-safe aliases are translated back to Runner's canonical MCP tool names locally.
- Write tools create immutable, evidence-backed proposals. Approval and apply tools are not exposed to the model.
- Eligible plan and spend-alert proposals are policy-approved automatically and applied by a separate trusted service.

### Demo data coverage

- Every service line has 365 days of deterministic daily data, voice, SMS, and roaming usage.
- Every account has 24 monthly invoices, with corresponding settled payments for paid invoices.
- The helpdesk seed includes 12 cases across six tenants with open, waiting, resolved, and closed states; family-member cases remain principal-scoped.
- Customer-visible cases carry realistic categories, priorities, progress summaries, versions, and seeded customer/agent notes.
- The principal-scoped usage projection includes reviewed member name, relationship, line label, and device dimensions. This lets Runner aggregate by customer-facing labels without permitting grouping on UUID identifiers.
- Family owners and managers can compare all entitled members. A family member receives only their own projected usage rows even when the same grouped question is asked.
- If Runner refuses a proposed plan, the agent must inspect the refusal and retry with reviewed operations. A refusal is never treated as evidence that no data exists. If no corrected reviewed route is available, the answer explains the boundary and offers answerable alternatives.

## JWT/login behavior

- Passwords are bcrypt hashes in PostgreSQL.
- Login resolves the principal's active account membership. A principal with multiple memberships must select an account number.
- The backend signs a 15-minute RS256 JWT containing issuer, both MCP audiences, principal `sub`, tenant `tenant_id`, role, and scopes.
- The browser receives the JWT only as an `HttpOnly`, `SameSite=Strict` cookie. JavaScript never reads or stores it.
- The backend validates the cookie on every chat request and passes the token server-to-server to Runner.
- Runner receives only `/run/secrets/jwt-public.pem`; the private key remains in the backend-only `.runtime` mount.
- Local HTTP uses `COOKIE_SECURE=false`. Set it to `true` behind HTTPS in a real deployment.

## Synapsor MCP tools

Production Explore exposes exactly:

- `app.describe_data`
- `app.explore_data`

Reviewed actions expose these OpenAI-safe aliases:

- `account__inspect_subscription`
- `account__propose_plan_change`
- `line__inspect_service_settings`
- `line__propose_roaming_change`
- `billing__inspect_preferences`
- `billing__propose_autopay_change`
- `billing__propose_paperless_change`
- `billing__propose_spend_alert_change`
- `support__inspect_case`
- `support__propose_case_note`

The model can inspect and propose. It cannot approve proposals, run `apply`, execute SQL, alter a boundary, or access credentials.

## Demo Runner Trace UI

After login, the browser opens a two-pane customer-support workspace. While an answer is running, the authenticated `POST /api/chat/stream` endpoint sends newline-delimited JSON events to the browser. The trace panel animates the real model → Runner → model path as each recorder event occurs; it does not estimate or fabricate progress. Every event displays its syntax-highlighted JSON payload immediately.

Every completed answer also includes an ephemeral **Runner Trace** that demonstrates the model/data boundary:

- **What the model saw:** the effective system instructions, conversation input items, prior tool results, raw model output items, and model-visible MCP tool catalog.
- **What the model sent:** the OpenAI-safe tool name and exact arguments emitted by the model.
- **What Runner received:** the canonical Synapsor MCP tool name after local alias translation and the exact request arguments.
- **What the model got back:** Runner's structured MCP response, status, and request duration.
- **Run summary:** model turns, Runner calls, token usage, and end-to-end duration.

The interface includes expandable trace stages, interaction history for the current browser page, copy controls, responsive mobile presentation, and syntax-highlighted JSON. Click **View Runner calls** below an assistant answer to open the complete inspector. From there, choose `0.25×`, `0.5×`, or `1×` and click **Replay flow** to reconstruct the event sequence at a readable speed; replay uses the event offsets captured during the real request. Click **Inspect sequence** to load every event immediately, then use **Previous** and **Next** to move between highlighted payloads. The same navigation appears after a live run and can pause an in-progress replay for closer inspection.

This is intentionally a demonstration feature, not a recommended production transcript store. Trace data is streamed only to the authenticated request and retained only in page memory; the non-streaming `/api/chat` endpoint remains available for API compatibility. Browser trace history is discarded on reload. It is not written to the telecom database or Runner's audit ledger. Credential-shaped fields are redacted, JWTs remain outside model context, and the built-in Agents SDK trace exporter is configured not to include sensitive generation/tool payloads.

Runner's production query-audit ledger remains the authoritative durable audit surface. It stores bounded metadata and fingerprints rather than result rows or chat transcripts; use the audit commands later in this README to inspect it.

## Approval and execution policy

| Change | Approval | Limits |
| --- | --- | --- |
| Plan change | Policy auto-approval | Destination base price at most 16,500 cents; at most 3 approvals and 30,000 total destination cents per tenant/day |
| Spend-alert threshold | Policy auto-approval | Threshold at most 25,000 cents; at most 10 approvals and 100,000 total threshold cents per tenant/day |
| Customer case note | Policy auto-approval | Trimmed note at most 1,000 characters; fixed bounded-note policy unit; at most 20 notes per tenant/day; trusted handler computes the stored length |
| International roaming | Human `support_supervisor` | Exact reviewed boolean change and version guard |
| Autopay | Human `support_supervisor` | Exact reviewed boolean change and version guard |
| Paperless billing | Human `support_supervisor` | Exact reviewed boolean change and version guard |

When a policy ceiling is exceeded, Runner leaves the proposal in review instead of rejecting or applying it. Policy approval is separate from execution. `runner-auto-apply` polls approved proposals, and Runner rechecks proposal state, tenant/principal scope, target version, allowlisted columns, policy limits, and idempotency before invoking the signed app handler.

Runner 1.7.11's built-in supervised worker intentionally excludes app-owned HTTP handlers. This project therefore runs the guarded `apply --all-approved` operator path in a dedicated trusted container; no apply capability is exposed over MCP.

The app-owned handler additionally validates:

- bearer authentication, HMAC body signature, and a five-minute timestamp window;
- principal and tenant recovered from Runner's protected proposal ledger;
- account role and PostgreSQL RLS visibility;
- exact action/table/primary key, tenant guard, version guard, and allowed patch columns;
- reviewed plan catalog prices or bounded spend-alert values;
- one-row update, durable idempotency receipt, and read-model synchronization.

## Inspect production Explore readiness

```bash
docker compose \
  --env-file .env \
  exec runner-explore \
  synapsor-runner doctor \
    --config /app/synapsor/explore/synapsor.runner.json \
    --transport streamable-http \
    --host 0.0.0.0 \
    --preflight \
    --trusted-tls-proxy \
    --json
```

Confirm the server advertises only two Explore tools:

```bash
docker compose \
  --env-file .env \
  logs --tail=100 runner-explore
```

Confirm the action catalog:

```bash
docker compose \
  --env-file .env \
  exec runner-actions \
  synapsor-runner tools list --aliases \
    --config /app/synapsor/actions/synapsor.runner.json
```

## Explore evidence and rejection/query audit

### Direct Runner query-audit commands on the host

Run these in a separate normal terminal while PostgreSQL is running. They use the globally installed `synapsor-runner` and inspect the same shared audit ledger used by the application.

First, enter the Explore project directory and configure access to the host-exposed control database:

```bash
cd synapsor/explore

export SYNAPSOR_CONTROL_DATABASE_URL='postgresql://synapsor_control:synapsor_control_pw@127.0.0.1:5544/synapsor_control'
export SYNAPSOR_EXPLORE_BUDGET_HMAC_KEY='mY8kz2NwR4vQ7sL1pT6cX9bF3hJ5dG0uA2eK8nP4qWs'
```

Open the interactive query-audit TUI:

```bash
synapsor-runner query-audit browse \
  --since 24h \
  --config ./synapsor.runner.json
```

List recent audit records as JSON:

```bash
synapsor-runner query-audit list \
  --since 24h \
  --limit 50 \
  --json \
  --config ./synapsor.runner.json
```

Show only refused or failed Explore attempts:

```bash
synapsor-runner query-audit list \
  --since 24h \
  --outcome refused \
  --limit 50 \
  --json \
  --config ./synapsor.runner.json

synapsor-runner query-audit list \
  --since 24h \
  --outcome failed \
  --limit 50 \
  --json \
  --config ./synapsor.runner.json
```

Inspect one record from the list in detail, or export it:

```bash
synapsor-runner query-audit show AUDIT_ID \
  --details \
  --config ./synapsor.runner.json

synapsor-runner query-audit export AUDIT_ID \
  --format json \
  --output ./query-audit.json \
  --config ./synapsor.runner.json
```

If `POSTGRES_PORT` or `SYNAPSOR_EXPLORE_BUDGET_HMAC_KEY` was overridden at startup, use those same values here.

### Interactive TUI

Return to the repository root before using the Compose commands. Compose supplies the shared control-store URL and HMAC key inside the container.

```bash
cd ../..
```

```bash
docker compose \
  --env-file .env \
  exec runner-explore \
  synapsor-runner evidence browse \
    --since 24h \
    --config /app/synapsor/explore/synapsor.runner.json
```

```bash
docker compose \
  --env-file .env \
  exec runner-explore \
  synapsor-runner query-audit browse \
    --since 24h \
    --config /app/synapsor/explore/synapsor.runner.json
```

`evidence browse` shows released results. `query-audit browse` also shows refusals and failures that never produced evidence.

### Noninteractive JSON

```bash
docker compose \
  --env-file .env \
  exec -T runner-explore \
  synapsor-runner query-audit list \
    --since 24h --limit 50 --json \
    --config /app/synapsor/explore/synapsor.runner.json
```

## Proposal, receipt, and auto-apply inspection

List proposals:

```bash
docker compose \
  --env-file .env \
  exec runner-actions \
  synapsor-runner proposals list \
    --config /app/synapsor/actions/synapsor.runner.json
```

Show one proposal in detail:

```bash
docker compose \
  --env-file .env \
  exec runner-actions \
  synapsor-runner proposals show PROPOSAL_ID --details \
    --config /app/synapsor/actions/synapsor.runner.json
```

Approve a review-required proposal as the local demo operator. The trusted auto-applier then handles execution:

```bash
docker compose \
  --env-file .env \
  exec runner-actions \
  synapsor-runner proposals approve PROPOSAL_ID --yes \
    --config /app/synapsor/actions/synapsor.runner.json
```

Watch apply outcomes and receipt hashes:

```bash
docker compose \
  --env-file .env \
  logs --follow runner-auto-apply backend
```

## Logs and health

```bash
docker compose \
  --env-file .env \
  ps

docker compose \
  --env-file .env \
  logs --tail=150 backend runner-explore runner-actions runner-auto-apply
```

## Stop without deleting data

```bash
docker compose \
  --env-file .env \
  down
```

Do not add `--volumes`; the named PostgreSQL volume preserves all data.

To intentionally destroy and reseed all database/control data, use `docker compose down --volumes` only after confirming that data loss is wanted. The next startup runs every SQL file under `db/init` again.

## Project layout

```text
backend/app/
  auth.py                         JWT issue/validation and public-key export
  database.py                     auth, chat, RLS, receipt, and ledger pools
  prompt.py                       customer-service system prompt
  services/agent_service.py       Agents SDK and both MCP clients
  services/mcp_alias_server.py    canonical Explore -> OpenAI-safe aliases
  services/writeback_service.py   guarded app-owned writeback handler
  static/                         responsive login and chat UI
db/init/
  00_roles_and_control.sql        least-privilege roles and control database
  01_schema.sql                   multi-tenant telecom schema
  02_security.sql                 RLS, grants, and trusted helper functions
  03_seed.sql                     six tenants and substantial usage/billing data
  04_customer_explore_projection.sql direct tenant/principal Explore read model
  05_expand_usage_demo.sql        idempotent year-long usage and member dimensions
scripts/start.sh                  one-command, ordered Docker startup
scripts/compile-actions.sh        compile DSL into the canonical action contract
synapsor/explore/                 reviewed production Explore boundary/config
synapsor/actions/                 authored action DSL, generated contract, runtime wiring
```

## Deployment boundary

This Compose setup binds the browser, database, and Runner ports to loopback for local development. The production Explore profile is enabled and passes Runner preflight, but `--trusted-tls-proxy` assumes an actual TLS-terminating reverse proxy in a real deployment. Before exposing it beyond this machine:

- terminate TLS at a trusted proxy and firewall direct Runner access;
- protect the proxy-to-Runner network and preserve the original Host;
- set `COOKIE_SECURE=true`;
- move database passwords, handler tokens, HMAC keys, and JWT keys to a secret manager;
- replace demo users/passwords and configure a real identity provider and operator identity;
- use managed PostgreSQL backups, observability, and credential rotation.

OpenAI references: [Agents SDK MCP guide](https://openai.github.io/openai-agents-python/mcp/) and [`gpt-5.6-luna` model reference](https://developers.openai.com/api/docs/models/gpt-5.6-luna).
