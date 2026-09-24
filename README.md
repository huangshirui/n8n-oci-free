# n8n on Oracle Cloud Free Tier

Production configuration for an Oracle Cloud x86 **1 vCPU / 1 GiB RAM** instance.

Architecture:

- Cloudflare Proxy is the public edge for the n8n hostname.
- Traefik terminates origin TLS with a Cloudflare Origin CA certificate and reverse-proxies to n8n.
- Traefik trusts forwarded headers only from Cloudflare's published IP ranges; n8n uses two proxy hops for Cloudflare → Traefik.
- n8n runs in regular mode with production workflow concurrency capped at 2.
- Binary workflow data is stored on the persistent filesystem rather than kept in memory.
- Code/Python tasks run in the external task-runner container with concurrency capped at 1.
- PostgreSQL is external to this VM.
- GitHub is the source of truth for deployment configuration and scripts.
- `.env`, database password, local workflow files, exports, Docker volumes, certificates, and private keys are never committed.

The small nginx `static` service is retained temporarily for existing `*.txt` URLs. Moving those files to Cloudflare R2 is a separate migration.

## Repository layout

```text
.
├── docker-compose.yml
├── traefik/
│   └── tls.yml
├── .env.example
├── .gitignore
├── scripts/
│   ├── upgrade.sh
│   ├── export.sh
│   ├── import.sh
│   └── install-n8n.sh
├── secrets/
│   ├── postgres_password.txt.example
│   └── traefik/                 # local Origin CA cert/key; ignored by Git
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

## Cloudflare Origin TLS

The n8n DNS record is expected to stay **Proxied** in Cloudflare. Traefik no longer runs ACME/Let's Encrypt itself.

1. In Cloudflare open **SSL/TLS → Origin Server → Create Certificate**.
2. Create an Origin CA certificate covering the n8n hostname.
3. Save the PEM certificate as `/opt/n8n-compose/secrets/traefik/n8n-origin.crt`.
4. Save the private key as `/opt/n8n-compose/secrets/traefik/n8n-origin.key`.
5. Run:

   ```bash
   chmod 600 secrets/traefik/n8n-origin.crt secrets/traefik/n8n-origin.key
   ```

6. After Traefik is serving the Origin CA certificate successfully, set Cloudflare SSL/TLS encryption mode to **Full (strict)**.

Traefik trusts `X-Forwarded-*` only from Cloudflare's published IPv4/IPv6 ranges. With the request path Cloudflare → Traefik → n8n, `N8N_PROXY_HOPS=2` lets n8n resolve the original client address without blindly trusting forwarded headers from direct origin clients.

## Resource profile

The Compose configuration is intentionally conservative for a 1 GiB VM:

```text
n8n production workflow concurrency: 2
external task-runner concurrency:     1
runner V8 old-space target:           128 MiB
runner container memory limit:        256 MiB
execution history:                    14 days / max 5000
execution detail display limit:       20 MiB
binary data:                           filesystem
```

`/home/node/.n8n` is backed by the persistent `n8n_data` volume, so filesystem binary data survives container recreation and is pruned with normal execution-data pruning.

For the 1 GiB host, a 2 GiB emergency swap file with low swappiness is recommended to absorb occasional AI/file-processing memory spikes without treating swap as normal working memory.

## Deploy

Before deployment, make sure these local files exist and are non-empty:

```text
secrets/postgres_password.txt
secrets/traefik/n8n-origin.crt
secrets/traefik/n8n-origin.key
```

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

The script fetches `origin/main`, requires a clean tracked working tree, fast-forwards when needed, checks required local secret files, validates Compose, pulls the declared images, recreates only changed services, waits for n8n to become healthy, and prunes only dangling images. It does not run `docker compose down`.

If Git is already current, the script still validates and reconciles the running deployment. This makes a failed deployment recoverable after fixing a missing local certificate or other runtime prerequisite.

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

The Docker named `n8n_data` volume keeps its identity because the Compose project remains in the same directory. The old `traefik_data` ACME volume is no longer referenced after the Origin CA migration; leave it in place until the new TLS path is verified, then remove it manually if desired.

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
mkdir -p /opt/n8n-compose/secrets/traefik
printf '%s' 'YOUR_EXISTING_POSTGRES_PASSWORD' > /opt/n8n-compose/secrets/postgres_password.txt
chmod 600 /opt/n8n-compose/secrets/postgres_password.txt
```

Create the Cloudflare Origin CA certificate/key before applying the new Compose configuration, then save them at:

```text
/opt/n8n-compose/secrets/traefik/n8n-origin.crt
/opt/n8n-compose/secrets/traefik/n8n-origin.key
```

`SSL_EMAIL` is no longer used because Traefik no longer performs ACME issuance.

Then attach the existing directory to GitHub:

```bash
cd /opt/n8n-compose

git init
git remote add origin https://github.com/huangshirui/n8n-oracle.git
git fetch origin main
git checkout -f -B main origin/main
git branch --set-upstream-to=origin/main main
```

The checkout replaces tracked configuration files but leaves ignored runtime files such as `.env`, `secrets/postgres_password.txt`, `secrets/traefik/*`, and `local-files/*` in place.

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
