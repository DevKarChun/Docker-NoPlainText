# Docker + Bitwarden Secrets Template

A reusable template for running Docker containers where **no plaintext passwords ever touch your disk or Git repository**. Secrets are managed in Bitwarden (with a beautiful UI and cloud sync) and injected into Docker at runtime via a generated `.env` file.

## How It Works

```
┌──────────────────────────────────────────────────────────────┐
│  Bitwarden Cloud (managed, synced, backed up for you)        │
│  - Login: "postgres"  →  username + password                 │
│  - Login: "redis"     →  password                            │
│  - Login: "stripe"    →  password                            │
└──────────────────────────────────────────────────────────────┘
                            │
                            │ syncs to
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  Local encrypted cache on your Mac (works offline)           │
└──────────────────────────────────────────────────────────────┘
                            │
                            │ ./generate-env.sh reads
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  bitwarden-secrets.json  →  maps env vars to BW items        │
│  (e.g. DB_PASSWORD → item "postgres", field "password")      │
└──────────────────────────────────────────────────────────────┘
                            │
                            │ writes
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  .env  (gitignored, never committed)                         │
│  DB_USER=myapp_user                                          │
│  DB_PASSWORD=supersecret                                     │
└──────────────────────────────────────────────────────────────┘
                            │
                            │ docker compose reads
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  docker-compose.yml                                          │
│  POSTGRES_USER: ${DB_USER}                                   │
│  POSTGRES_PASSWORD: ${DB_PASSWORD}                           │
└──────────────────────────────────────────────────────────────┘
```

## Responsibilities (Strict Separation)

| Component | Responsibility |
|-----------|---------------|
| `bitwarden-secrets.json` | Declares **which** Bitwarden items map to **which** env vars. Safe to commit. |
| `generate-env.sh` | Talks to Bitwarden, writes `.env`. Knows nothing about Docker. |
| `.env` | Holds plaintext key-value pairs. Auto-generated, **gitignored**. |
| `docker-compose.yml` | Defines containers, reads from `.env`. Knows nothing about Bitwarden. |

This separation means you can swap the secret source (e.g. 1Password, AWS Secrets Manager) by only rewriting `generate-env.sh`.

## Prerequisites

Install these once on your Mac:

```bash
# Bitwarden CLI
brew install bitwarden-cli

# JSON parser (used by the script)
brew install jq

# Docker Desktop (if not already installed)
brew install --cask docker
```

Also make sure you have a [Bitwarden account](https://vault.bitwarden.com) and the Bitwarden Desktop App installed (for easy UI management of secrets).

## Project Structure

```
your-project/
├── .gitignore                  ← ignores .env
├── README.md                   ← this file
├── bitwarden-secrets.json      ← maps env vars → Bitwarden items
├── generate-env.sh             ← fetches secrets, writes .env
├── docker-compose.yml          ← container definitions
└── .env                        ← auto-generated (gitignored)
```

## Quick Start

```bash
# 1. Create Bitwarden items (see "Step 1" below)

# 2. Configure which secrets you need
#    Edit bitwarden-secrets.json

# 3. Generate .env from Bitwarden
./generate-env.sh

# 4. Start containers
docker compose up -d
```

## Detailed Setup

### Step 1: Create Bitwarden Items

Open the Bitwarden Desktop App or Web Vault and create **Login** items for each secret your project needs.

Example for a Postgres database:

| Field | Value |
|-------|-------|
| **Name** | `postgres` |
| **Username** | `myapp_user` |
| **Password** | `your-strong-password-here` |

Example for Redis:

| Field | Value |
|-------|-------|
| **Name** | `redis` |
| **Username** | *(leave blank)* |
| **Password** | `your-redis-password` |

> **Tip:** Item names must match **exactly** (case-sensitive) what you put in `bitwarden-secrets.json`.

### Step 2: Configure `bitwarden-secrets.json`

This file declares the mapping between environment variable names and Bitwarden items.

```json
{
  "secrets": {
    "DB_USER": {
      "item": "postgres",
      "field": "username"
    },
    "DB_PASSWORD": {
      "item": "postgres",
      "field": "password"
    },
    "REDIS_PASSWORD": {
      "item": "redis",
      "field": "password"
    },
    "STRIPE_API_KEY": {
      "item": "stripe",
      "field": "password"
    }
  }
}
```

**Field reference:**

| Key | Meaning |
|-----|---------|
| `DB_USER` (top-level) | The environment variable name Docker Compose will see |
| `item` | The exact name of the Login item in your Bitwarden vault |
| `field` | Either `"username"` or `"password"` |

### Step 3: Generate `.env`

```bash
./generate-env.sh
```

The script will:
1. Unlock Bitwarden (prompts for master password if needed)
2. Read `bitwarden-secrets.json`
3. Fetch each secret from your local Bitwarden cache
4. Write them to `.env`

Output:
```
📖 Reading secrets from Bitwarden...
  ✓ DB_USER
  ✓ DB_PASSWORD
  ✓ REDIS_PASSWORD
  ✓ STRIPE_API_KEY
✅ .env file generated with 4 secrets.
```

### Step 4: Start Docker

```bash
docker compose up -d
```

Docker Compose automatically reads `.env` and substitutes `${VAR}` references in your `docker-compose.yml`.

## Example `docker-compose.yml`

```yaml
services:
  db:
    image: postgres:16
    environment:
      POSTGRES_USER: ${DB_USER}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
    command: redis-server --requirepass ${REDIS_PASSWORD}
    ports:
      - "6379:6379"

  app:
    image: your-app:latest
    environment:
      DATABASE_URL: postgres://${DB_USER}:${DB_PASSWORD}@db:5432/mydb
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      STRIPE_API_KEY: ${STRIPE_API_KEY}
    ports:
      - "3000:3000"
    depends_on:
      - db
      - redis

volumes:
  pgdata:
```

## Daily Usage

### First time in a new terminal

```bash
./generate-env.sh     # prompts for Bitwarden master password once
docker compose up -d
```

### Subsequent runs in the same terminal

```bash
docker compose up -d  # .env already exists, just start
```

### Restarting containers (no secret refresh)

```bash
docker compose restart
```

### Refreshing secrets after changing them in Bitwarden

```bash
./generate-env.sh     # re-fetches from Bitwarden
docker compose up -d  # restarts with new values
```

### Stopping everything

```bash
docker compose down
```

## Adding a New Secret

1. **Create the item in Bitwarden** (e.g. Login named `aws` with access key as password)

2. **Add the mapping** to `bitwarden-secrets.json`:
   ```json
   "AWS_ACCESS_KEY": {
     "item": "aws",
     "field": "password"
   }
   ```

3. **Use it** in `docker-compose.yml`:
   ```yaml
   environment:
     AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY}
   ```

4. **Regenerate `.env`**:
   ```bash
   ./generate-env.sh
   ```

## The Files (Copy-Paste Reference)

### `.gitignore`

```gitignore
.env
```

### `generate-env.sh`

```bash
#!/bin/bash
# Purpose: Read bitwarden-secrets.json and generate .env file
# Usage: ./generate-env.sh

set -euo pipefail

CONFIG_FILE="bitwarden-secrets.json"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config file '$CONFIG_FILE' not found." >&2
  exit 1
fi

if ! command -v jq &> /dev/null; then
  echo "❌ 'jq' is required. Install with: brew install jq" >&2
  exit 1
fi

if ! bw unlock --check &>/dev/null; then
  echo "🔓 Unlocking Bitwarden..."
  export BW_SESSION=$(bw unlock --raw)
fi

echo "📖 Reading secrets from Bitwarden..."
> .env

jq -c '.secrets | to_entries[]' "$CONFIG_FILE" | while IFS= read -r entry; do
  ENV_VAR=$(echo "$entry" | jq -r '.key')
  ITEM_NAME=$(echo "$entry" | jq -r '.value.item')
  FIELD=$(echo "$entry" | jq -r '.value.field')

  if [ "$FIELD" = "username" ]; then
    VALUE=$(bw get username "$ITEM_NAME")
  else
    VALUE=$(bw get password "$ITEM_NAME")
  fi

  if [ -z "$VALUE" ]; then
    echo "❌ Failed to fetch $ENV_VAR from Bitwarden item '$ITEM_NAME'." >&2
    exit 1
  fi

  echo "$ENV_VAR=$VALUE" >> .env
  echo "  ✓ $ENV_VAR"
done

echo "✅ .env file generated with $(wc -l < .env) secrets."
```

Don't forget: `chmod +x generate-env.sh`

## Security Notes

- ✅ **`.env` is gitignored** — never committed
- ✅ **No plaintext passwords in `docker-compose.yml`** — safe to commit
- ✅ **Bitwarden syncs to cloud** — managed backups, no self-hosting
- ✅ **Local encrypted cache** — works offline
- ⚠️ **`.env` exists on disk** while containers run — readable by anyone with access to your Mac
- ⚠️ **Secrets are visible via `docker inspect`** and inside the running container's environment
- 💡 For stricter isolation (secrets hidden even from running containers), consider Docker's native `secrets` with `tmpfs` mounts

## Troubleshooting

### `❌ Failed to fetch ... from Bitwarden`
- Verify the `item` name in `bitwarden-secrets.json` matches **exactly** (case-sensitive) the name in your Bitwarden vault
- Confirm the item actually exists in your vault
- Run `bw sync` manually to refresh the local cache

### `❌ 'jq' is required`
```bash
brew install jq
```

### `❌ bw: command not found`
```bash
brew install bitwarden-cli
```

### Containers fail to start with empty values
- You probably ran `docker compose up -d` directly without running `./generate-env.sh` first
- Check that `.env` exists and contains the expected variables: `cat .env`

### `bw unlock --check` keeps failing
- Your session expired. Just run `./generate-env.sh` again — it will prompt for your master password and create a new session.

### Want to auto-unlock on every new terminal?
Add to your `~/.zshrc`:
```bash
if ! bw unlock --check &> /dev/null; then
  export BW_SESSION=$(bw unlock --raw)
fi
```

## Using This Template in a New Project

```bash
mkdir my-new-project && cd my-new-project

# Copy these files from the template:
# - .gitignore
# - generate-env.sh (then chmod +x)
# - bitwarden-secrets.json (edit for your project)
# - docker-compose.yml (write your own)
# - README.md (this file)

# Then:
./generate-env.sh
docker compose up -d
```

That's it. Same workflow, every project.