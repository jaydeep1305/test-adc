#!/bin/bash
# Usage:
#   Import single domain : bash ia.sh /path/to/exports/2026-04-21_11-05-42/fotocircle.com
#   Import ALL domains   : bash ia.sh /path/to/exports/2026-04-21_11-05-42

INPUT="$1"

if [ -z "$INPUT" ] || [ ! -d "$INPUT" ]; then
  echo "Usage: bash ia.sh /path/to/export/DOMAIN_NAME"
  echo "       bash ia.sh /path/to/export/TIMESTAMP_FOLDER"
  exit 1
fi

# ─── READ CREDS ───────────────────────────────────────────────────────────────
ENV_FILE="/var/www/larapush/.env"
DB_HOST=$(grep '^DB_HOST=' "$ENV_FILE" | cut -d'=' -f2)
DB_PORT=$(grep '^DB_PORT=' "$ENV_FILE" | cut -d'=' -f2)
DB_NAME=$(grep '^DB_DATABASE=' "$ENV_FILE" | cut -d'=' -f2)
DB_USER=$(grep '^DB_USERNAME=' "$ENV_FILE" | cut -d'=' -f2)
DB_PASS=$(grep '^DB_PASSWORD=' "$ENV_FILE" | cut -d'=' -f2)

MYSQL="mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASS $DB_NAME --skip-column-names --batch"

import_domain() {
  local DOMAIN_DIR="$1"
  local DOMAIN_JSON="$DOMAIN_DIR/domain.json"
  local TOKENS_CSV="$DOMAIN_DIR/tokens.csv"

  [ ! -f "$DOMAIN_JSON" ] && echo "  ✗ Missing domain.json in $DOMAIN_DIR" && return
  [ ! -f "$TOKENS_CSV" ]  && echo "  ✗ Missing tokens.csv in $DOMAIN_DIR"  && return

  local name=$(jq -r '.name' "$DOMAIN_JSON")
  local email=$(jq -r '.email' "$DOMAIN_JSON")
  local apiKey=$(jq -r '.apiKey' "$DOMAIN_JSON")
  local projectId=$(jq -r '.projectId' "$DOMAIN_JSON")
  local messagingSenderId=$(jq -r '.messagingSenderId' "$DOMAIN_JSON")
  local appId=$(jq -r '.appId' "$DOMAIN_JSON")
  local serverKey=$(jq -r '.serverKey' "$DOMAIN_JSON")
  local serviceAccountFile=$(jq -r '.serviceAccountFile' "$DOMAIN_JSON")
  local publicKey=$(jq -r '.publicKey' "$DOMAIN_JSON")
  local privateKey=$(jq -r '.privateKey' "$DOMAIN_JSON")
  local serviceAccount=$(jq -r '.serviceAccount' "$DOMAIN_JSON")

  echo ""
  echo "━━━ Importing: $name"

  # Check if domain already exists
  local EXISTING_ID=$($MYSQL -e "SELECT id FROM domains WHERE name='$name' LIMIT 1;")

  if [ -n "$EXISTING_ID" ]; then
    echo "  ⚠ Already exists (id=$EXISTING_ID), skipping domain insert."
    DOMAIN_ID=$EXISTING_ID
  else
    $MYSQL -e "
      INSERT INTO domains
        (name, email, apiKey, projectId, messagingSenderId, appId, serverKey,
         serviceAccountFile, publicKey, privateKey, serviceAccount,
         enabled, status, created_at, updated_at)
      VALUES (
        $(jq -Rn --arg v "$name" '$v'),
        $(jq -Rn --arg v "$email" '$v'),
        $(jq -Rn --arg v "$apiKey" '$v'),
        $(jq -Rn --arg v "$projectId" '$v'),
        $(jq -Rn --arg v "$messagingSenderId" '$v'),
        $(jq -Rn --arg v "$appId" '$v'),
        $(jq -Rn --arg v "$serverKey" '$v'),
        $(jq -Rn --arg v "$serviceAccountFile" '$v'),
        $(jq -Rn --arg v "$publicKey" '$v'),
        $(jq -Rn --arg v "$privateKey" '$v'),
        $(jq -Rn --arg v "$serviceAccount" '$v'),
        1, 'active', NOW(), NOW()
      );
    "
    DOMAIN_ID=$($MYSQL -e "SELECT id FROM domains WHERE name='$name' LIMIT 1;")
    echo "  ✓ Domain inserted (id=$DOMAIN_ID)"
  fi

  # Import tokens
  local TOKEN_COUNT=0
  local SKIP_HEADER=1

  while IFS=',' read -r token ip country state browser_name operating_system platform created_at version endpoint p256dh auth url active; do
    [ $SKIP_HEADER -eq 1 ] && SKIP_HEADER=0 && continue
    [ -z "$token" ] && continue

    $MYSQL -e "
      INSERT IGNORE INTO fcm_tokens
        (domain_id, token, ip, country, state, browser_name, operating_system,
         platform, created_at, version, endpoint, p256dh, auth, url, active)
      VALUES (
        $DOMAIN_ID,
        '$token','$ip','$country','$state',
        '$browser_name','$operating_system','$platform',
        '$created_at','$version',
        '$endpoint','$p256dh','$auth','$url','$active'
      );
    " 2>/dev/null

    ((TOKEN_COUNT++))
  done < "$TOKENS_CSV"

  echo "  ✓ $TOKEN_COUNT tokens imported"
}

# ─── DETECT: single domain folder OR timestamp folder ─────────────────────────
if [ -f "$INPUT/domain.json" ]; then
  # Single domain folder passed
  import_domain "$INPUT"
else
  # Timestamp folder — loop all subdirectories
  FOUND=0
  for DOMAIN_DIR in "$INPUT"/*/; do
    [ -d "$DOMAIN_DIR" ] && import_domain "$DOMAIN_DIR" && ((FOUND++))
  done
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "✓ Done! $FOUND domains processed."
fi
