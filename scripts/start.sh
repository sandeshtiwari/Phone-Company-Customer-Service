#!/usr/bin/env sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ENV_FILE=${1:-"$PROJECT_ROOT/.env"}

if [ ! -f "$ENV_FILE" ]; then
  echo "Environment file not found: $ENV_FILE" >&2
  echo "Copy .env.example to .env and add OPENAI_API_KEY, then try again." >&2
  exit 1
fi

mkdir -p "$PROJECT_ROOT/.runtime"
cd "$PROJECT_ROOT"

echo "Compiling and validating the reviewed Synapsor action contract..."
"$PROJECT_ROOT/scripts/compile-actions.sh"

echo "Starting PostgreSQL, the Synapsor control store, and the web app..."
docker compose --env-file "$ENV_FILE" up -d --build \
  postgres schema-migrate control-store-init backend

echo "Waiting for the backend to publish Runner's JWT verification key..."
attempt=0
while [ ! -f "$PROJECT_ROOT/.runtime/jwt-public.pem" ]; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 60 ]; then
    echo "The JWT public key was not created. Inspect the backend logs:" >&2
    echo "  docker compose --env-file $ENV_FILE logs backend" >&2
    exit 1
  fi
  sleep 1
done

echo "Starting production Explore, reviewed actions, and auto-apply..."
docker compose --env-file "$ENV_FILE" up -d --build \
  runner-explore runner-actions runner-auto-apply

docker compose --env-file "$ENV_FILE" ps
APP_ADDRESS=$(docker compose --env-file "$ENV_FILE" port backend 8000)
echo
echo "Luna Telecom is ready at http://$APP_ADDRESS"
