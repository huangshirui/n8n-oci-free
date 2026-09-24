#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${N8N_PROJECT_DIR:-/opt/n8n-compose}"
BACKUP_ROOT="${N8N_BACKUP_DIR:-$HOME/n8n-backups}"
DECRYPTED=false

if [[ "${1:-}" == "--decrypted" ]]; then
  DECRYPTED=true
elif [[ $# -gt 0 ]]; then
  echo "Usage: $0 [--decrypted]"
  exit 1
fi

cd "$PROJECT_DIR"
EXPORT_DIR="$BACKUP_ROOT/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$EXPORT_DIR"
chmod 700 "$BACKUP_ROOT" "$EXPORT_DIR"

echo "Export directory: $EXPORT_DIR"

docker compose exec -T n8n n8n export:workflow --all --output=/tmp/workflows.json
docker compose cp n8n:/tmp/workflows.json "$EXPORT_DIR/workflows.json"
docker compose exec -T n8n rm -f /tmp/workflows.json

if [[ "$DECRYPTED" == true ]]; then
  echo "WARNING: exporting credentials in PLAINTEXT"
  docker compose exec -T n8n n8n export:credentials --all --decrypted --output=/tmp/credentials.json
else
  docker compose exec -T n8n n8n export:credentials --all --output=/tmp/credentials.json
fi

docker compose cp n8n:/tmp/credentials.json "$EXPORT_DIR/credentials.json"
docker compose exec -T n8n rm -f /tmp/credentials.json
chmod 600 "$EXPORT_DIR"/*.json

if command -v jq >/dev/null 2>&1; then
  jq empty "$EXPORT_DIR/workflows.json"
  jq empty "$EXPORT_DIR/credentials.json"
fi

cat > "$EXPORT_DIR/README.txt" <<EOF
Created: $(date -Is)
n8n version: $(docker compose exec -T n8n n8n --version | tr -d '\r')
Credentials decrypted: $DECRYPTED

This is an application-level workflow/credential export, NOT a complete n8n instance backup.
Do not commit this directory to Git.
EOF
chmod 600 "$EXPORT_DIR/README.txt"

echo "Export complete: $EXPORT_DIR"
