# PG Rate Portal — Hostinger VPS Deployment Guide
## pgrates.unifiedpaygate.com | 195.179.193.43

---

## OVERVIEW

```
Your VPS (Ubuntu 24.04)
├── Docker (n8n on port 5678)          ← already running, untouched
├── Nginx (reverse proxy)              ← add pgrates config block
├── Node.js + PM2 (pg-portal:3011)    ← new, runs alongside n8n
└── Let's Encrypt SSL (certbot)       ← free SSL for subdomain
```

---

## STEP 1: DNS — Add Subdomain in Hostinger

1. Login to Hostinger → **Domains → unifiedpaygate.com → DNS Zone**
2. Add a new record:
   ```
   Type  : A
   Name  : pgrates
   Value : 195.179.193.43
   TTL   : 300
   ```
3. Save. DNS propagates in 5–30 minutes.
   Verify: `ping pgrates.unifiedpaygate.com` (from any terminal)

---

## STEP 2: Get files onto VPS from GitHub

1. Go to Hostinger → VPS → **Terminal**
2. Run:
   ```bash
   apt-get install -y git
   git clone https://github.com/BalajiMAnandhababu/pgrates.git /opt/pgrates
   cd /opt/pgrates/pg-portal-vps
   chmod +x deploy.sh update.sh
   ```

---

## STEP 3: Google Cloud Setup (one-time, ~10 minutes)

### 3a. Create Google Cloud Project
1. Go to https://console.cloud.google.com
2. Click project dropdown → **New Project**
3. Name: `unified-paygate-portal` → **Create**

### 3b. Enable Google Sheets API
1. In the search bar, type **"Google Sheets API"**
2. Click → **Enable**

### 3c. Create Service Account
1. Go to **IAM & Admin → Service Accounts**
2. Click **+ Create Service Account**
   - Name: `pg-portal-service`
   - Click **Create and Continue**
   - Role: **Basic → Editor**
   - Click **Done**

### 3d. Download JSON Key
1. Click the service account you just created
2. **Keys** tab → **Add Key → Create new key → JSON**
3. Download the JSON file — open it in Notepad
4. You'll need the entire contents in Step 4

### 3e. Share your Google Sheet with the service account
1. Open the `PG_MASTER_DATA_v2.xlsx` file in Google Drive as a Google Sheet
2. Click **Share** → paste the service account email
   (looks like: `pg-portal-service@unified-paygate-portal.iam.gserviceaccount.com`)
3. Role: **Editor** → **Send**
4. Copy the Sheet ID from the URL:
   `https://docs.google.com/spreadsheets/d/COPY_THIS_PART/edit`

---

## STEP 4: Configure .env on VPS

```bash
nano /tmp/pg-portal-vps/.env.example
```

Edit these three values:
```
GOOGLE_SHEET_ID=paste_your_sheet_id_here
ADMIN_PIN=2580
GOOGLE_SERVICE_ACCOUNT_JSON=paste_entire_json_here_on_one_line
```

**Important for the JSON:** Open the downloaded JSON file, select all, copy — then paste it as ONE single line after `GOOGLE_SERVICE_ACCOUNT_JSON=`. No line breaks inside the JSON value.

Save: `Ctrl+O` → Enter → `Ctrl+X`

---

## STEP 5: Run the deployment script

```bash
cd /opt/pgrates/pg-portal-vps
bash deploy.sh
```

This script will:
- ✓ Install Node.js 20 (if not present)
- ✓ Install PM2 globally
- ✓ Create `/var/www/pg-portal/`
- ✓ Copy all files
- ✓ Copy your `.env` values
- ✓ Run `npm install`
- ✓ Add Nginx config for `pgrates.unifiedpaygate.com`
- ✓ Obtain free SSL certificate via certbot
- ✓ Start the app with PM2
- ✓ Configure PM2 to restart on server reboot

**Expected output at the end:**
```
✓ Deployment complete!
  App:     http://127.0.0.1:3011
  Public:  https://pgrates.unifiedpaygate.com
```

---

## STEP 6: Fill in .env properly

After deploy.sh runs, edit the real .env:
```bash
nano /var/www/pg-portal/.env
```
Fill in GOOGLE_SHEET_ID, ADMIN_PIN, GOOGLE_SERVICE_ACCOUNT_JSON — same as Step 4.

Then restart:
```bash
pm2 restart pg-portal
pm2 logs pg-portal --lines 20
```

Look for: `✓ PG Rate Portal running on http://127.0.0.1:3011`

---

## STEP 7: Verify everything works

```bash
# Check app is running
pm2 status

# Test API directly
curl http://127.0.0.1:3011/api/health

# Check nginx
nginx -t
systemctl status nginx

# Test public URL (after DNS + SSL)
curl https://pgrates.unifiedpaygate.com/api/health
```

Expected health response:
```json
{"ok":true,"ts":"2025-05-15T...","sheet":true}
```

---

## FUTURE UPDATES (when you change portal code)

Push your changes to GitHub, then on the VPS run:
```bash
bash /opt/pgrates/pg-portal-vps/update.sh
```

This pulls the latest code from GitHub, reinstalls dependencies, and restarts the app. Preserves `.env` and nginx config.

---

## PM2 CHEATSHEET

```bash
pm2 status                    # see all running apps
pm2 logs pg-portal            # live logs
pm2 logs pg-portal --lines 50 # last 50 lines
pm2 restart pg-portal         # restart after code change
pm2 stop pg-portal            # stop (nginx returns 502)
pm2 start pg-portal           # start again
pm2 monit                     # live CPU/memory dashboard
```

---

## NGINX CHEATSHEET

```bash
nginx -t                      # test config
systemctl reload nginx         # apply config changes (no downtime)
systemctl restart nginx        # full restart
cat /var/log/nginx/pgrates.error.log   # check errors
```

---

## n8n SAFETY NOTE

Your n8n is running in Docker on port 5678. This deployment:
- Uses port **3011** — no conflict
- Does NOT touch Docker or n8n config
- Adds one new Nginx site config — existing n8n nginx config is untouched

---

## TROUBLESHOOTING

| Problem | Fix |
|---------|-----|
| `502 Bad Gateway` | `pm2 status` — app may be crashed. `pm2 logs pg-portal` |
| `SSL certificate error` | DNS not propagated yet. Wait 30 min, re-run certbot |
| `{"error":"...credentials..."}` | GOOGLE_SERVICE_ACCOUNT_JSON in .env is malformed. Must be one line |
| `sheet:false` in health check | GOOGLE_SHEET_ID not set in .env |
| App not starting after reboot | `pm2 startup` then `pm2 save` |
