#!/usr/bin/env bash
set -Eeuo pipefail

# Ubuntu bootstrap for a fresh Oracle Cloud VM.
# Repository access (SSH deploy key or another Git credential) must already work.

REPO_URL="${N8N_REPO_URL:-git@github.com:huangshirui/n8n-oracle.git}"
PROJECT_DIR="${N8N_PROJECT_DIR:-/opt/n8n-compose}"
DEPLOY_USER="${SUDO_USER:-${USER}}"

if [[ $EUID -ne 0 ]]; then
  echo "Run with sudo: sudo $0"
  exit 1
fi

if [[ ! -r /etc/os-release ]] || ! grep -qi '^ID=ubuntu' /etc/os-release; then
  echo "This installer currently supports Ubuntu only."
  exit 1
fi

apt-get update
apt-get install -y ca-certificates curl git openssl

for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
  apt-get remove -y "$pkg" 2>/dev/null || true
done

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
printf 'deb [arch=%s signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu %s stable\n' \
  "$(dpkg --print-architecture)" \
  "$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")" \
  > /etc/apt/sources.list.d/docker.list

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
systemctl enable --now docker
usermod -aG docker "$DEPLOY_USER"

if [[ -e "$PROJECT_DIR" && -n "$(find "$PROJECT_DIR" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  echo "$PROJECT_DIR already exists and is not empty; refusing to overwrite it."
  exit 1
fi

mkdir -p "$PROJECT_DIR"
chown "$DEPLOY_USER:$DEPLOY_USER" "$PROJECT_DIR"
sudo -u "$DEPLOY_USER" git clone "$REPO_URL" "$PROJECT_DIR"

cd "$PROJECT_DIR"
mkdir -p secrets local-files static
chmod +x scripts/*.sh
chown -R "$DEPLOY_USER:$DEPLOY_USER" "$PROJECT_DIR"

if [[ ! -f .env ]]; then
  cp .env.example .env
  chmod 600 .env
fi

if [[ ! -f secrets/postgres_password.txt ]]; then
  install -m 600 /dev/null secrets/postgres_password.txt
fi

chown "$DEPLOY_USER:$DEPLOY_USER" .env secrets/postgres_password.txt

cat <<EOF
Bootstrap complete.

Before starting n8n:
  1. Edit $PROJECT_DIR/.env
  2. Put the PostgreSQL password in $PROJECT_DIR/secrets/postgres_password.txt
  3. Generate N8N_RUNNERS_AUTH_TOKEN with: openssl rand -hex 32
  4. Log out/in once so $DEPLOY_USER gets Docker group membership, or run Docker with sudo for this session.
  5. Run: cd $PROJECT_DIR && docker compose config --quiet && docker compose up -d
EOF
