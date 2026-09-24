# n8n on Oracle Cloud Free Tier

Production configuration for an Oracle Cloud x86 **1 vCPU / 1 GiB RAM** instance.

Architecture:

- Traefik terminates TLS.
- n8n runs in regular mode with production workflow concurrency capped at 2.
- Code/Python tasks run in the external task-runner container with concurrency capped at 1.
- PostgreSQL is external to this VM.
- GitHub is the source of truth for deployment configuration and scripts.
- `.env`, database password, local workflow files, exports, Docker volumes, and TLS material are never committed.

## Repository layout

```text
.
├── docker-compose.yml
├── .env.example
├── .gitignore
├── scripts/
│   ├── upgrade.sh
│   ├── export.sh
│   ├── import.sh
│   └── install-n8n.sh
├── secrets/
│   └── postgres_password.txt.example
├── local-files/
└── static/
```

## Local runtime files

Create `.env` from the example and keep it only on the server:

```bash
cp .env.example .env
chmod 600 .env
openssl rand -hex 32
```

Put the generated value in `N8N_RUNNERS_AUTH_TOKEN`.

Create the PostgreSQL secret:

```bash
printf '%s' 'YOUR_POSTGRES_PASSWORD' > secrets/postgres_password.txt
chmod 600 secrets/postgres_password.txt
```

Do **not** casually introduce or replace `N8N_ENCRYPTION_KEY` on an existing instance. Preserve the existing `n8n_data` Docker volume/encryption material so existing credentials stay readable.

## Deploy

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --remove-orphans
docker compose ps
```

## Upgrade from GitHub

The deployment does not follow Docker's floating `stable` tag. The n8n and runner versions are pinned directly in `docker-compose.yml`, so Git remains the deployment source of truth.

Upgrade by changing **both** n8n image tags to the same reviewed version, committing the change to `main`, and then running on the server:

```bash
/opt/n8n-compose/scripts/upgrade.sh
```

The script fetches `origin/main`, requires a clean tracked working tree, fast-forwards the checkout, validates Compose, pulls the declared images, recreates only changed services, waits for n8n to become healthy, and prunes only dangling images. It does not run `docker compose down`.

## Workflow / credential export

```bash
./scripts/export.sh
```

Exports go to `~/n8n-backups/<timestamp>/` and are excluded from Git. Credentials remain encrypted by default.

For a deliberate portable plaintext credential export:

```bash
./scripts/export.sh --decrypted
```

Treat that directory as a secret. The export scripts are **not** a complete instance backup; PostgreSQL and persistent n8n state require their own backup policy.

## Import

```bash
./scripts/import.sh ~/n8n-backups/20260924_120000
```

The importer requires explicit confirmation. n8n imports retain IDs, so matching IDs in the target database can be overwritten.

## GitHub access on the server

This repository is intended to be public. A production server therefore needs no GitHub credentials for read-only deployment.

Use the HTTPS remote:

```bash
git ls-remote https://github.com/huangshirui/n8n-oracle.git
```

## Convert the existing /opt/n8n-compose directory to Git

The Docker named volumes keep their identity because the Compose project remains in the same directory.

First keep copies of the current local configuration:

```bash
cd /opt/n8n-compose
cp docker-compose.yml ~/n8n-compose.docker-compose.pre-git.bak
cp .env ~/n8n-compose.env.pre-git.bak
```

Make sure the existing `.env` contains these non-secret DB settings required by the new Compose file:

```dotenv
DB_POSTGRESDB_HOST=10.0.0.54
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n_user
```

Create the local password secret from the password used by the existing deployment:

```bash
mkdir -p /opt/n8n-compose/secrets
printf '%s' 'YOUR_EXISTING_POSTGRES_PASSWORD' > /opt/n8n-compose/secrets/postgres_password.txt
chmod 600 /opt/n8n-compose/secrets/postgres_password.txt
```

Then attach the existing directory to GitHub:

```bash
cd /opt/n8n-compose

git init
git remote add origin https://github.com/huangshirui/n8n-oracle.git
git fetch origin main
git checkout -f -B main origin/main
git branch --set-upstream-to=origin/main main
```

The checkout replaces tracked configuration files but leaves ignored runtime files such as `.env`, `secrets/postgres_password.txt`, and `local-files/*` in place.

Move the old root-level maintenance scripts out of the directory after the checkout:

```bash
mkdir -p ~/n8n-compose-old-scripts
for f in upgrade.sh export.sh import.sh install-n8n.sh; do
  [[ -e "$f" ]] && mv "$f" ~/n8n-compose-old-scripts/
done
```

Validate before changing any running container:

```bash
docker compose config --quiet
git status --short
```

Then apply the tracked configuration without taking the whole stack down:

```bash
docker compose pull
docker compose up -d --remove-orphans
docker compose ps
curl -fsS http://127.0.0.1:5678/healthz
```

After this one-time conversion, normal deployment becomes:

```bash
cd /opt/n8n-compose
./scripts/upgrade.sh
```
