#!/bin/bash
# deploy.sh — Run this once on your VPS to install the PG Rate Portal
# Usage: bash deploy.sh
# Run as root or with sudo

set -e  # exit on any error

REPO_URL="https://github.com/BalajiMAnandhababu/pgrates.git"
REPO_DIR="/opt/pgrates"

echo ""
echo "════════════════════════════════════════════"
echo "  PG Rate Portal — VPS Deployment Script"
echo "  pgrates.unifiedpaygate.com"
echo "════════════════════════════════════════════"
echo ""

# ── 0. Clone or update repo from GitHub ──────────────────────────────────────
if ! command -v git &>/dev/null; then
  echo "→ Installing git..."
  apt-get install -y git
fi

if [ -d "$REPO_DIR/.git" ]; then
  echo "→ Updating repo from GitHub..."
  git -C "$REPO_DIR" pull
else
  echo "→ Cloning repo from GitHub..."
  git clone "$REPO_URL" "$REPO_DIR"
fi

SCRIPT_DIR="$REPO_DIR/pg-portal-vps"
echo "✓ Source ready at $SCRIPT_DIR"
echo ""

# ── 1. Install Node.js 20 (if not installed) ─────────────────────────────────
if ! command -v node &>/dev/null; then
  echo "→ Installing Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
else
  echo "✓ Node.js $(node -v) already installed"
fi

# ── 2. Install PM2 (if not installed) ────────────────────────────────────────
if ! command -v pm2 &>/dev/null; then
  echo "→ Installing PM2..."
  npm install -g pm2
else
  echo "✓ PM2 already installed"
fi

# ── 3. Create app directory ───────────────────────────────────────────────────
echo "→ Setting up /var/www/pg-portal..."
mkdir -p /var/www/pg-portal/public
mkdir -p /var/log/pg-portal

# ── 4. Copy files ─────────────────────────────────────────────────────────────
echo "→ Copying app files..."
cp -r "$SCRIPT_DIR/server"            /var/www/pg-portal/
cp -r "$SCRIPT_DIR/public"            /var/www/pg-portal/
cp    "$SCRIPT_DIR/package.json"      /var/www/pg-portal/
cp    "$SCRIPT_DIR/ecosystem.config.js" /var/www/pg-portal/

# ── 5. Create .env if not exists ─────────────────────────────────────────────
if [ ! -f /var/www/pg-portal/.env ]; then
  cp "$SCRIPT_DIR/.env.example" /var/www/pg-portal/.env
  echo ""
  echo "⚠️  .env file created at /var/www/pg-portal/.env"
  echo "   You MUST edit it with your values before starting the app."
  echo "   Run: nano /var/www/pg-portal/.env"
  echo ""
fi

# ── 6. Install npm dependencies ───────────────────────────────────────────────
echo "→ Installing npm dependencies..."
cd /var/www/pg-portal
npm install --omit=dev

# ── 7. Nginx config (HTTP-only first, certbot adds SSL) ───────────────────────
echo "→ Setting up Nginx config..."
cat > /etc/nginx/sites-available/pgrates.unifiedpaygate.com << 'NGINXCONF'
server {
    listen 80;
    server_name pgrates.unifiedpaygate.com;

    location / {
        proxy_pass         http://127.0.0.1:3011;
        proxy_http_version 1.1;
        proxy_set_header   Upgrade $http_upgrade;
        proxy_set_header   Connection 'upgrade';
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto $scheme;
        proxy_cache_bypass $http_upgrade;
        proxy_read_timeout 30s;
    }

    access_log /var/log/nginx/pgrates.access.log;
    error_log  /var/log/nginx/pgrates.error.log;
}
NGINXCONF

if [ ! -f /etc/nginx/sites-enabled/pgrates.unifiedpaygate.com ]; then
  ln -s /etc/nginx/sites-available/pgrates.unifiedpaygate.com \
        /etc/nginx/sites-enabled/pgrates.unifiedpaygate.com
fi

nginx -t && echo "✓ Nginx config valid"

# ── 8. Start / reload nginx ───────────────────────────────────────────────────
if systemctl is-active --quiet nginx; then
  systemctl reload nginx
else
  systemctl start nginx
fi
echo "✓ Nginx running"

# ── 9. SSL with certbot ───────────────────────────────────────────────────────
if ! command -v certbot &>/dev/null; then
  echo "→ Installing certbot..."
  apt-get install -y certbot python3-certbot-nginx
fi

echo ""
echo "→ Obtaining SSL certificate for pgrates.unifiedpaygate.com..."
echo "  (Domain DNS A record must point to 195.179.193.43 before this works)"
echo ""
certbot --nginx -d pgrates.unifiedpaygate.com --non-interactive --agree-tos \
  --email admin@unifiedpaygate.com --redirect || {
  echo "⚠️  SSL failed — DNS may not be set yet."
  echo "   Run manually after DNS propagates: certbot --nginx -d pgrates.unifiedpaygate.com"
}

# ── 10. Start app with PM2 ────────────────────────────────────────────────────
echo "→ Starting app with PM2..."
cd /var/www/pg-portal
pm2 start ecosystem.config.js
pm2 save

# Make PM2 start on reboot
pm2 startup systemd -u root --hp /root | tail -1 | bash || true

echo ""
echo "════════════════════════════════════════════"
echo "  ✓ Deployment complete!"
echo "════════════════════════════════════════════"
echo ""
echo "  App:     http://127.0.0.1:3011"
echo "  Public:  https://pgrates.unifiedpaygate.com"
echo "  Logs:    pm2 logs pg-portal"
echo "  Status:  pm2 status"
echo "  Restart: pm2 restart pg-portal"
echo ""
echo "  ⚠️  Before the site works:"
echo "  1. Edit .env:  nano /var/www/pg-portal/.env"
echo "  2. Restart:    pm2 restart pg-portal"
echo ""
