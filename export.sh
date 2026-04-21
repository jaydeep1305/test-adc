#!/bin/bash

# ─── READ CREDS FROM .ENV ─────────────────────────────────────────────────────
ENV_FILE="/var/www/larapush/.env"

DB_HOST=$(grep '^DB_HOST=' "$ENV_FILE" | cut -d'=' -f2)
DB_PORT=$(grep '^DB_PORT=' "$ENV_FILE" | cut -d'=' -f2)
DB_NAME=$(grep '^DB_DATABASE=' "$ENV_FILE" | cut -d'=' -f2)
DB_USER=$(grep '^DB_USERNAME=' "$ENV_FILE" | cut -d'=' -f2)
DB_PASS=$(grep '^DB_PASSWORD=' "$ENV_FILE" | cut -d'=' -f2)

EXPORT_DIR="/var/www/larapush/storage/app/exports"
mkdir -p "$EXPORT_DIR"

MYSQL="mysql -h $DB_HOST -P $DB_PORT -u $DB_USER -p$DB_PASS $DB_NAME --skip-column-names --batch"

# ─── GET ALL ACTIVE DOMAINS ───────────────────────────────────────────────────
DOMAINS=$($MYSQL -e "SELECT id, name FROM domains WHERE enabled = 1 AND status = 'active' AND name IS NOT NULL AND name != '';")

if [ -z "$DOMAINS" ]; then
  echo "No active domains found."
  exit 0
fi

# ─── EXPORT TOKENS PER DOMAIN ─────────────────────────────────────────────────
while IFS=$'\t' read -r DOMAIN_ID DOMAIN_NAME; do
  DOMAIN_NAME=$(echo "$DOMAIN_NAME" | tr -d '[:space:]')
  [ -z "$DOMAIN_NAME" ] && continue

  TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
  OUT_FILE="$EXPORT_DIR/tokens_${DOMAIN_NAME}_${TIMESTAMP}.csv"

  echo "Exporting: $DOMAIN_NAME (id=$DOMAIN_ID)"

  # Write header first
  echo "token,ip,country,state,browser_name,operating_system,platform,created_at,version,endpoint,p256dh,auth,url,active" > "$OUT_FILE"

  # Append data rows (tab -> comma)
  $MYSQL -e "
    SELECT
      token,
      COALESCE(ip, ''),
      COALESCE(country, ''),
      COALESCE(state, ''),
      COALESCE(browser_name, ''),
      COALESCE(operating_system, ''),
      COALESCE(platform, ''),
      created_at,
      version,
      COALESCE(endpoint, ''),
      COALESCE(p256dh, ''),
      COALESCE(auth, ''),
      COALESCE(url, ''),
      active
    FROM fcm_tokens
    WHERE domain_id = $DOMAIN_ID
    ORDER BY id ASC
  " | sed 's/\t/,/g' >> "$OUT_FILE"

  COUNT=$(( $(wc -l < "$OUT_FILE") - 1 ))
  echo "  ✓ $COUNT tokens -> $OUT_FILE"

done <<< "$DOMAINS"

echo ""
echo "Done! Exports in: $EXPORT_DIR"
