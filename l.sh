#!/bin/bash

# ─────────────────────────────────────────
# Laravel + Nginx Setup Script
# Usage: sudo bash setup.sh <old_domain> <new_domain> [laravel_path] [php_version]
# Example: sudo bash setup.sh push.newsfirst.news push.knowledge-arrow.com /var/www/larapush 8.2
# ─────────────────────────────────────────

# ── Validate Required Args ─────────────────
if [ -z "$1" ] || [ -z "$2" ]; then
    echo "❌ Usage: sudo bash setup.sh <old_domain> <new_domain> [laravel_path] [php_version]"
    echo "   Example: sudo bash setup.sh push.newsfirst.news push.knowledge-arrow.com /var/www/larapush 8.2"
    exit 1
fi

# ── CONFIG (with defaults) ─────────────────
OLD_DOMAIN="$1"
DOMAIN="$2"
LARAVEL_PATH="${3:-/var/www/larapush}"   # default: /var/www/larapush
PHP_VERSION="${4:-8.2}"                  # default: 8.2
# ─────────────────────────────────────────

CONF_FILE="/etc/nginx/conf.d/${DOMAIN}.conf"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " Old Domain:   $OLD_DOMAIN"
echo " New Domain:   $DOMAIN"
echo " Laravel Path: $LARAVEL_PATH"
echo " PHP Version:  $PHP_VERSION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Replace Old Domain in Project Files ──
echo "[1/7] Replacing old domain references in project files..."
cd "$LARAVEL_PATH"

for FILE in "public/firebase-messaging-sw.js" ".env"; do
    if [ -f "$FILE" ]; then
        sed -i "s#https://${OLD_DOMAIN}#https://${DOMAIN}#g" "$FILE"
        echo "    ✅ Updated: $FILE"
    else
        echo "    ⚠️  File not found, skipping: $FILE"
    fi
done

# ── 2. Create Nginx Config ─────────────────
echo "[2/7] Creating Nginx config..."
cat > "$CONF_FILE" <<EOF
server {
    listen 80;
    listen [::]:80;

    server_name ${DOMAIN};
    root ${LARAVEL_PATH}/public;

    index index.php index.html index.htm;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php$ {
        include fastcgi_params;
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF
echo "    ✅ Nginx config created at $CONF_FILE"

# ── 3. Update APP_URL in .env ──────────────
echo "[3/7] Updating APP_URL in .env..."
ENV_FILE="${LARAVEL_PATH}/.env"
if [ -f "$ENV_FILE" ]; then
    sed -i "s|^APP_URL=.*|APP_URL=https://${DOMAIN}|" "$ENV_FILE"
    echo "    ✅ APP_URL updated"
else
    echo "    ⚠️  .env file not found at $ENV_FILE — skipping"
fi

# ── 4. Fix Permissions ─────────────────────
echo "[4/7] Fixing permissions..."
chown -R www-data:www-data "$LARAVEL_PATH"
chmod -R 755 "${LARAVEL_PATH}/storage" "${LARAVEL_PATH}/bootstrap/cache"
echo "    ✅ Permissions fixed"

# ── 5. Clear Laravel Cache ─────────────────
echo "[5/7] Clearing Laravel cache..."
cd "$LARAVEL_PATH"
php artisan config:clear
php artisan cache:clear
php artisan route:clear
php artisan view:clear
php artisan config:cache
echo "    ✅ Cache cleared"

# ── 6. Test & Reload Nginx ─────────────────
echo "[6/7] Testing Nginx config..."
nginx -t
if [ $? -eq 0 ]; then
    systemctl reload nginx
    echo "    ✅ Nginx reloaded"
else
    echo "    ❌ Nginx config has errors — fix before continuing"
    exit 1
fi

# ── 7. SSL with Certbot ────────────────────
echo "[7/7] Setting up SSL certificate..."
if command -v certbot &> /dev/null; then
    certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "admin@${DOMAIN}"
    echo "    ✅ SSL certificate issued"
else
    echo "    ⚠️  Certbot not found. Install it with:"
    echo "         sudo apt install certbot python3-certbot-nginx -y"
    echo "    Then run: sudo certbot --nginx -d $DOMAIN"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo " ✅ All done! Visit: https://$DOMAIN"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
