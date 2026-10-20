#!/bin/bash
# Purpose: Read bitwarden-secrets.json and generate .env file
# Usage: ./generate-env.sh

set -euo pipefail

CONFIG_FILE="bitwarden-secrets.json"

# Check if config exists
if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config file '$CONFIG_FILE' not found." >&2
  exit 1
fi

# Check if jq is installed (needed to parse JSON)
if ! command -v jq &> /dev/null; then
  echo "❌ 'jq' is required but not installed." >&2
  echo "   Install with: brew install jq" >&2
  exit 1
fi

# Unlock Bitwarden if needed
if ! bw unlock --check &>/dev/null; then
  echo "🔓 Unlocking Bitwarden..."
  export BW_SESSION=$(bw unlock --raw)
fi

echo "📖 Reading secrets from Bitwarden..."

# Clear existing .env
> .env

# Parse JSON and fetch each secret
jq -c '.secrets | to_entries[]' "$CONFIG_FILE" | while IFS= read -r entry; do
  ENV_VAR=$(echo "$entry" | jq -r '.key')
  ITEM_NAME=$(echo "$entry" | jq -r '.value.item')
  FIELD=$(echo "$entry" | jq -r '.value.field')
  
  # Fetch from Bitwarden
  if [ "$FIELD" = "username" ]; then
    VALUE=$(bw get username "$ITEM_NAME")
  else
    VALUE=$(bw get password "$ITEM_NAME")
  fi
  
  # Validate
  if [ -z "$VALUE" ]; then
    echo "❌ Failed to fetch $ENV_VAR from Bitwarden item '$ITEM_NAME'." >&2
    exit 1
  fi
  
  # Write to .env
  echo "$ENV_VAR=$VALUE" >> .env
  echo "  ✓ $ENV_VAR"
done

echo "✅ .env file generated with $(wc -l < .env) secrets."