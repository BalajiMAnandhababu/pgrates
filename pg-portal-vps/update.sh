#!/bin/bash
# update.sh — Push code updates to the running portal (run from VPS)
# Usage: bash update.sh
# Does NOT touch .env or restart nginx

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "→ Updating pg-portal..."
cp -r "$SCRIPT_DIR/server" /var/www/pg-portal/
cp -r "$SCRIPT_DIR/public" /var/www/pg-portal/
cp    "$SCRIPT_DIR/package.json" /var/www/pg-portal/
cp    "$SCRIPT_DIR/ecosystem.config.js" /var/www/pg-portal/

cd /var/www/pg-portal
npm install --omit=dev

pm2 restart pg-portal
echo "✓ pg-portal restarted"
pm2 logs pg-portal --lines 10 --nostream
