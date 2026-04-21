#!/bin/bash

ENV_FILE="/var/www/larapush/.env"
DB_HOST=$(grep '^DB_HOST=' "$ENV_FILE" | cut -d'=' -f2)
DB_PORT=$(grep '^DB_PORT=' "$ENV_FILE" | cut -d'=' -f2)
DB_NAME=$(grep '^DB_DATABASE=' "$ENV_FILE" | cut -d'=' -f2)
DB_USER=$(grep '^DB_USERNAME=' "$ENV_FILE" | cut -d'=' -f2)
DB_PASS=$(grep '^DB_PASSWORD=' "$ENV_FILE" | cut -d'=' -f2)

TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
EXPORT_DIR="/var/www/larapush/storage/app/exports/$TIMESTAMP"
mkdir -p "$EXPORT_DIR"

if ! command -v jq &>/dev/null; then apt-get install -y jq -q; fi

MYSQL="mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASS $DB_NAME --skip-column-names --batch"

DOMAINS=$($MYSQL -e "SELECT id, name FROM domains WHERE name IS NOT NULL AND name != '';")

[ -z "$DOMAINS" ] && echo "No domains found." && exit 0

TOTAL_DOMAINS=0
TOTAL_TOKENS=0
SKIPPED=0

echo "Export started: $TIMESTAMP"
echo "Output: $EXPORT_DIR"
echo "────────────────────────────────────────"

while IFS=$'\t' read -r DOMAIN_ID DOMAIN_NAME; do
  DOMAIN_NAME=$(echo "$DOMAIN_NAME" | tr -d '[:space:]')
  [ -z "$DOMAIN_NAME" ] && continue

  DOMAIN_DIR="$EXPORT_DIR/$DOMAIN_NAME"

  # ── Fetch domain config fields individually ──────────────────────────────
  name=$($MYSQL -e "SELECT COALESCE(name,'') FROM domains WHERE id=$DOMAIN_ID LIMIT 1")
  email=$($MYSQL -e "SELECT COALESCE(email,'') FROM domains WHERE id=$DOMAIN_ID LIMIT 1")
  apiKey=$($MYSQL -e "SELECT COALESCE(apiKey,'') FROM domains WHERE id=$DOMAIN_ID LIMIT 1")
  projectId=$($MYSQL -e "SELECT COALESCE(projectId,'') FROM domains WHERE id=$DOMAIN_ID LIMIT 1")
  messagingSenderId=$($MYSQL -e "SELECT COALESCE(messagingSenderId,'') FROM domains WHERE id=$DOMAIN_ID LIMIT 1")
  appId=$($MYSQL -e "SELECT COALESCE(appId,'') FROM domains WHERE id=$DOMAIN_ID LIMIT 1")
  serverKey=$($MYSQL -e "SELECT COALESCE(serverKey,'') FROM domains WHERE id=$DOMAIN_ID LIMIT 1")
  serviceAccountFile=$($MYSQL -e "SELECT COALESCE(serviceAccountFile,'') FROM domains WHERE id=$DOMAIN_ID LIMIT 1")
  publicKey=$($MYSQL -e "SELECT COALESCE(publicKey,'') FROM domains WHERE id=$DOMAIN_ID LIMIT 1")
  privateKey=$($MYSQL -e "SELECT COALESCE(privateKey,'') FROM domains WHERE id=$DOMAIN_ID LIMIT 1")
  serviceAccount=$($MYSQL -e "SELECT COALESCE(serviceAccount,'') FROM domains WHERE id=$DOMAIN_ID LIMIT 1")

  # ── Skip if no serviceAccount ─────────────────────────────────────────────
  if [ -z "$(echo "$serviceAccount" | tr -d '[:space:]')" ]; then
    echo "  ⏭ Skipping $DOMAIN_NAME (no serviceAccount)"
    ((SKIPPED++))
    continue
  fi

  mkdir -p "$DOMAIN_DIR"

  # ── Export domain.json ────────────────────────────────────────────────────
  jq -n \
    --arg name "$name" \
    --arg email "$email" \
    --arg apiKey "$apiKey" \
    --arg projectId "$projectId" \
    --arg messagingSenderId "$messagingSenderId" \
    --arg appId "$appId" \
    --arg serverKey "$serverKey" \
    --arg serviceAccountFileInput "" \
    --arg serviceAccountFile "$serviceAccountFile" \
    --arg publicKey "$publicKey" \
    --arg privateKey "$privateKey" \
    --arg serviceAccount "$serviceAccount" \
    '{
      name: $name,
      email: $email,
      apiKey: $apiKey,
      projectId: $projectId,
      messagingSenderId: $messagingSenderId,
      appId: $appId,
      serverKey: $serverKey,
      serviceAccountFileInput: $serviceAccountFileInput,
      serviceAccountFile: $serviceAccountFile,
      publicKey: $publicKey,
      privateKey: $privateKey,
      serviceAccount: $serviceAccount
    }' > "$DOMAIN_DIR/domain.json"

  # ── Export tokens.csv ─────────────────────────────────────────────────────
  TOKENS_FILE="$DOMAIN_DIR/tokens.csv"
  echo "token,ip,country,state,browser_name,operating_system,platform,created_at,version,endpoint,p256dh,auth,url,active" > "$TOKENS_FILE"

  $MYSQL -e "
    SELECT
      token,
      COALESCE(ip,''),
      COALESCE(country,''),
      COALESCE(state,''),
      COALESCE(browser_name,''),
      COALESCE(operating_system,''),
      COALESCE(platform,''),
      created_at,
      version,
      COALESCE(endpoint,''),
      COALESCE(p256dh,''),
      COALESCE(auth,''),
      COALESCE(url,''),
      active
    FROM fcm_tokens
    WHERE domain_id = $DOMAIN_ID
    ORDER BY id ASC
  " | sed 's/\t/,/g' >> "$TOKENS_FILE"

  TOKEN_COUNT=$(( $(wc -l < "$TOKENS_FILE") - 1 ))
  echo "  ✓ $DOMAIN_NAME — $TOKEN_COUNT tokens"

  ((TOTAL_DOMAINS++))
  ((TOTAL_TOKENS += TOKEN_COUNT))

done <<< "$DOMAINS"

echo "────────────────────────────────────────"
echo "Exported: $TOTAL_DOMAINS domains | $TOTAL_TOKENS tokens | $SKIPPED skipped"
echo "Location: $EXPORT_DIR"
