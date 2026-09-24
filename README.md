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

Do **not** casually introduce or replace `N8N_ENCRYPTION_KEY` on an existing instance. Preserve the existing `n8n_data` volume/encryption material so existing credentials stay readable.

## Deploy

```bash
docker compose config --quiet
docker compose pull
docker compose up -d --remove-orphans
docker compose ps
```

## Upgrade from GitHub

The deployment does not follow Docker's floating `stable` tag. Upgrade n8n by changing `N8N_VERSION` in `.env.example`, reviewing the release, merging the change to `main`, and then running on the server:

```bash
/opt/n8n-compose/scripts/upgrade.sh
```

The script fetches `origin/main`, requires a clean tracked working tree, fast-forwards the checkout, validates Compose, pulls the declared images, recreates only changed services, waits for n8n to become healthy, and prunes only dangling images.

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

## Server Git authentication

For a production server that only needs to pull, use a repository-specific **read-only GitHub Deploy Key** rather than a personal access token. Add the server's public SSH key in GitHub repository **Settings → Deploy keys**, with write access disabled.
