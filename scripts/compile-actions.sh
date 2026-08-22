#!/usr/bin/env sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
ACTIONS_DIR="$PROJECT_ROOT/synapsor/actions"
DSL_FILE="$ACTIONS_DIR/telecom-actions.synapsor.sql"
CONTRACT_FILE="$ACTIONS_DIR/telecom-actions.contract.json"
CONFIG_FILE="$ACTIONS_DIR/synapsor.runner.json"

compile_with_runner() {
  synapsor-runner dsl validate "$DSL_FILE" --strict
  synapsor-runner dsl compile "$DSL_FILE" --out "$CONTRACT_FILE" --strict
  synapsor-runner contract validate "$CONTRACT_FILE"
  synapsor-runner config validate --config "$CONFIG_FILE"
}

if command -v synapsor-runner >/dev/null 2>&1; then
  compile_with_runner
else
  IMAGE_NAME=telecom-synapsor-contract-compiler:1.7.11
  echo "synapsor-runner is not installed on the host; using the project Docker image."
  docker build --tag "$IMAGE_NAME" "$PROJECT_ROOT/synapsor"
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    --volume "$ACTIONS_DIR:/work" \
    --workdir /work \
    "$IMAGE_NAME" \
    synapsor-runner dsl validate ./telecom-actions.synapsor.sql --strict
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    --volume "$ACTIONS_DIR:/work" \
    --workdir /work \
    "$IMAGE_NAME" \
    synapsor-runner dsl compile ./telecom-actions.synapsor.sql \
      --out ./telecom-actions.contract.json --strict
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    --volume "$ACTIONS_DIR:/work" \
    --workdir /work \
    "$IMAGE_NAME" \
    synapsor-runner contract validate ./telecom-actions.contract.json
  docker run --rm \
    --user "$(id -u):$(id -g)" \
    --volume "$ACTIONS_DIR:/work" \
    --workdir /work \
    "$IMAGE_NAME" \
    synapsor-runner config validate --config ./synapsor.runner.json
fi

echo "Reviewed action contract generated: $CONTRACT_FILE"
