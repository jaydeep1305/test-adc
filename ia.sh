#!/bin/bash
# Usage: bash import_domain.sh /path/to/exports/2026-04-21_13-00-00/fotocircle.com

DOMAIN_DIR="$1"

if [ -z "$DOMAIN_DIR" ] || [ ! -d "$DOMAIN_DIR" ]; then
  echo "Usage: bash import_domain.sh /path/to/export/DOMAIN_NAME"
  exit 1
fi

DOMAIN_JSON="$DOMAIN_DIR/domain.json"
TOKENS_CSV="$DOMAIN_DIR/tokens.csv"

if [ ! -f "$DOMAIN_JSON" ]; then echo "Missing: $DOMAIN_JSON"; exit 1; fi
if [ ! -f "$TOKENS_CSV" ];  then echo "Missing: $TOKENS_CSV";  exit 1; fi

# ─── READ CREDS ───────────────────────────────────────────────────────────────
ENV_FILE="/var/www/larapush/.env"
DB_HOST=$(grep '^DB_HOST=' "$ENV_FILE" | cut -d'=' -f2)
DB_PORT=$(grep '^DB_PORT=' "$ENV_FILE" | cut -d'=' -f2)
DB_NAME=$(grep '^DB_DATABASE=' "$ENV_FILE" | cut -d'=' -f2)
DB_USER=$(grep '^DB_USERNAME=' "$ENV_FILE" | cut -d'=' -f2)
DB_PASS=$(grep '^DB_PASSWORD=' "$ENV_FILE" | cut -d'=' -f2)

MYSQL="mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASS $DB_NAME --skip-column-names --batch"

# ─── PARSE domain.json ────────────────────────────────────────────────────────
name=$(jq -r '.name' "$DOMAIN_JSON")
email=$(jq -r '.email' "$DOMAIN_JSON")
apiKey=$(jq -r '.apiKey' "$DOMAIN_JSON")
projectId=$(jq -r '.projectId' "$DOMAIN_JSON")
messagingSenderId=$(jq -r '.messagingSenderId' "$DOMAIN_JSON")
appId=$(jq -r '.appId' "$DOMAIN_JSON")
serverKey=$(jq -r '.serverKey' "$DOMAIN_JSON")
serviceAccountFile=$(jq -r '.serviceAccountFile' "$DOMAIN_JSON")
publicKey=$(jq -r '.publicKey' "$DOMAIN_JSON")
privateKey=$(jq -r '.privateKey' "$DOMAIN_JSON")
serviceAccount=$(jq -r '.serviceAccount' "$DOMAIN_JSON")

echo "Importing domain: $name"

# ─── INSERT DOMAIN ────────────────────────────────────────────────────────────
# Check if domain already exists
EXISTING_ID=$($MYSQL -e "SELECT id FROM domains WHERE name='$name' LIMIT 1;")

if [ -n "$EXISTING_ID" ]; then
  echo "  ⚠ Domain already exists (id=$EXISTING_ID), skipping domain insert."
  DOMAIN_ID=$EXISTING_ID
else
  $MYSQL -e "
    INSERT INTO domains (name, email, apiKey, projectId, messagingSenderId, appId, serverKey, serviceAccountFile, publicKey, privateKey, serviceAccount, enabled, status, created_at, updated_at)
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

# ─── INSERT TOKENS ────────────────────────────────────────────────────────────
echo "  Importing tokens..."
TOKEN_COUNT=0
SKIP_HEADER=1

while IFS=',' read -r token ip country state browser_name operating_system platform created_at version endpoint p256dh auth url active; do
  # Skip header row
  if [ $SKIP_HEADER -eq 1 ]; then SKIP_HEADER=0; continue; fi
  [ -z "$token" ] && continue

  $MYSQL -e "
    INSERT IGNORE INTO fcm_tokens
      (domain_id, token, ip, country, state, browser_name, operating_system, platform, created_at, version, endpoint, p256dh, auth, url, active)
    VALUES (
      $DOMAIN_ID,
      '$token', '$ip', '$country', '$state',
      '$browser_name', '$operating_system', '$platform',
      '$created_at', '$version',
      '$endpoint', '$p256dh', '$auth',
      '$url', '$active'
    );
  " 2>/dev/null

  ((TOKEN_COUNT++))
done < "$TOKENS_CSV"

echo "  ✓ $TOKEN_COUNT tokens imported"
echo "Done: $name"
