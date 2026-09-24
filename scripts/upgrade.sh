#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${N8N_PROJECT_DIR:-/opt/n8n-compose}"
BRANCH="${N8N_GIT_BRANCH:-main}"
LOG_FILE="${N8N_UPGRADE_LOG:-$PROJECT_DIR/upgrade.log}"

log() {
  printf '%s - %s\n' "$(date '+%F %T')" "$*" | tee -a "$LOG_FILE"
}

cd "$PROJECT_DIR"

if [[ ! -d .git ]]; then
  log "ERROR: $PROJECT_DIR is not a Git working tree"
  exit 1
fi

if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
  log "ERROR: tracked files have local modifications; refusing to overwrite them"
  git status --short | tee -a "$LOG_FILE"
  exit 1
fi

OLD_COMMIT=$(git rev-parse HEAD)
git fetch --prune origin "$BRANCH"
NEW_COMMIT=$(git rev-parse "origin/$BRANCH")

if [[ "$OLD_COMMIT" != "$NEW_COMMIT" ]]; then
  log "Updating $OLD_COMMIT -> $NEW_COMMIT"
  git merge --ff-only "origin/$BRANCH"
else
  log "No Git changes; validating and reconciling the current deployment at $OLD_COMMIT"
fi

required_files=(
  "secrets/postgres_password.txt"
  "secrets/traefik/n8n-origin.crt"
  "secrets/traefik/n8n-origin.key"
)

for file in "${required_files[@]}"; do
  if [[ ! -s "$file" ]]; then
    log "ERROR: required local secret file is missing or empty: $PROJECT_DIR/$file"
    exit 1
  fi
done

docker compose config --quiet
docker compose pull
docker compose up -d --remove-orphans

for _ in $(seq 1 30); do
  status=$(docker inspect --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$(docker compose ps -q n8n)" 2>/dev/null || true)
  if [[ "$status" == "healthy" ]]; then
    log "Deployment healthy at $(git rev-parse HEAD)"
    docker image prune -f >/dev/null 2>&1 || true
    exit 0
  fi
  sleep 2
done

log "ERROR: n8n did not become healthy after deployment"
docker compose ps | tee -a "$LOG_FILE"
docker compose logs --tail=100 n8n traefik | tee -a "$LOG_FILE"
exit 1
