#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${N8N_PROJECT_DIR:-/opt/n8n-compose}"

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 <export_directory>"
  exit 1
fi

IMPORT_DIR=$(realpath "$1")
WORKFLOWS_FILE="$IMPORT_DIR/workflows.json"
CREDENTIALS_FILE="$IMPORT_DIR/credentials.json"

[[ -r "$WORKFLOWS_FILE" ]] || { echo "Missing $WORKFLOWS_FILE"; exit 1; }
[[ -r "$CREDENTIALS_FILE" ]] || { echo "Missing $CREDENTIALS_FILE"; exit 1; }

cd "$PROJECT_DIR"
CID=$(docker compose ps -q n8n)
[[ -n "$CID" ]] || { echo "n8n container is not running"; exit 1; }

cleanup() {
  docker compose exec -T n8n rm -f /tmp/n8n-import-workflows.json /tmp/n8n-import-credentials.json >/dev/null 2>&1 || true
}
trap cleanup EXIT

echo "Import source: $IMPORT_DIR"
echo "WARNING: imported IDs can overwrite workflows/credentials with the same IDs."
read -r -p "Continue? [y/N] " answer
[[ "$answer" =~ ^[Yy]$ ]] || exit 0

docker compose cp "$CREDENTIALS_FILE" n8n:/tmp/n8n-import-credentials.json
docker compose exec -T n8n n8n import:credentials --input=/tmp/n8n-import-credentials.json

docker compose cp "$WORKFLOWS_FILE" n8n:/tmp/n8n-import-workflows.json
docker compose exec -T n8n n8n import:workflow --input=/tmp/n8n-import-workflows.json

echo "Import complete. Review imported workflows in the UI before activating them."
