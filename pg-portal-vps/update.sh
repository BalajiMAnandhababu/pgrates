#!/bin/bash
# update.sh — Pull latest code from GitHub and restart the portal
# Usage: bash update.sh
# Does NOT touch .env or restart nginx

set -e

REPO_DIR="/opt/pgrates"
SCRIPT_DIR="$REPO_DIR/pg-portal-vps"

echo "→ Pulling latest code from GitHub..."
git -C "$REPO_DIR" pull

echo "→ Copying updated files..."
cp -r "$SCRIPT_DIR/server"             /var/www/pg-portal/
cp -r "$SCRIPT_DIR/public"             /var/www/pg-portal/
cp    "$SCRIPT_DIR/package.json"       /var/www/pg-portal/
cp    "$SCRIPT_DIR/ecosystem.config.js" /var/www/pg-portal/

cd /var/www/pg-portal
npm install --omit=dev

pm2 restart pg-portal
echo "✓ pg-portal restarted"
pm2 logs pg-portal --lines 10 --nostream
