#!/bin/bash
# deploy.sh — Run this once on your VPS to install the PG Rate Portal
# Usage: bash deploy.sh
# Run as root or with sudo

set -e  # exit on any error

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TRAEFIK_COMPOSE="/docker/n8n/docker-compose.yml"
TRAEFIK_DYNAMIC_DIR="/docker/n8n/traefik-dynamic"

echo ""
echo "════════════════════════════════════════════"
echo "  PG Rate Portal — VPS Deployment Script"
echo "  pgrates.unifiedpaygate.com"
echo "════════════════════════════════════════════"
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
cp -r "$SCRIPT_DIR/server"              /var/www/pg-portal/
cp -r "$SCRIPT_DIR/public"              /var/www/pg-portal/
cp    "$SCRIPT_DIR/package.json"        /var/www/pg-portal/
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

# ── 7. Traefik routing ────────────────────────────────────────────────────────
echo "→ Configuring Traefik route for pgrates.unifiedpaygate.com..."
mkdir -p "$TRAEFIK_DYNAMIC_DIR"

cat > "$TRAEFIK_DYNAMIC_DIR/pgrates.yml" << 'TRAEFIKCONF'
http:
  routers:
    pgrates:
      rule: "Host(`pgrates.unifiedpaygate.com`)"
      entrypoints:
        - websecure
      tls:
        certResolver: mytlschallenge
      service: pgrates-svc
  services:
    pgrates-svc:
      loadBalancer:
        servers:
          - url: "http://host.docker.internal:3011"
TRAEFIKCONF

# Add file provider + host.docker.internal to Traefik via override (if not already done)
OVERRIDE_FILE="/docker/n8n/docker-compose.override.yml"
if [ ! -f "$OVERRIDE_FILE" ]; then
  echo "→ Creating Traefik override for file provider..."
  cat > "$OVERRIDE_FILE" << 'OVERRIDE'
services:
  traefik:
    extra_hosts:
      - "host.docker.internal:host-gateway"
    command:
      - "--api.insecure=true"
      - "--providers.docker=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.mytlschallenge.acme.tlschallenge=true"
      - "--certificatesresolvers.mytlschallenge.acme.email=${SSL_EMAIL}"
      - "--certificatesresolvers.mytlschallenge.acme.storage=/letsencrypt/acme.json"
      - "--providers.file.directory=/traefik-dynamic"
      - "--providers.file.watch=true"
    volumes:
      - /docker/n8n/traefik-dynamic:/traefik-dynamic:ro
OVERRIDE
  echo "→ Restarting Traefik..."
  docker compose -f "$TRAEFIK_COMPOSE" up -d traefik
  echo "✓ Traefik updated"
else
  echo "✓ Traefik override already in place"
fi

# ── 8. Start app with PM2 ────────────────────────────────────────────────────
echo "→ Starting app with PM2..."
cd /var/www/pg-portal
if pm2 list | grep -q "pg-portal"; then
  pm2 restart pg-portal
else
  pm2 start ecosystem.config.js
fi
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
