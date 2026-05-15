// server/index.js
// PG Rate Portal — Express backend
// Runs on port 3011 (avoids conflict with n8n which uses 5678)

require('dotenv').config();
const express  = require('express');
const cors     = require('cors');
const path     = require('path');
const { google } = require('googleapis');

const app  = express();
const PORT = process.env.PORT || 3011;

const SHEET_ID    = process.env.GOOGLE_SHEET_ID;
const ADMIN_PIN   = process.env.ADMIN_PIN || '2580';

// ── Middleware ────────────────────────────────────────────────────────────────
app.use(cors({ origin: '*' }));
app.use(express.json());
app.use(express.static(path.join(__dirname, '../public')));

// ── Google Auth ───────────────────────────────────────────────────────────────
function getAuth() {
  const credentials = JSON.parse(process.env.GOOGLE_SERVICE_ACCOUNT_JSON);
  return new google.auth.GoogleAuth({
    credentials,
    scopes: ['https://www.googleapis.com/auth/spreadsheets'],
  });
}

async function getSheetsClient() {
  const auth = await getAuth();
  return google.sheets({ version: 'v4', auth });
}

// ── Sheet config ──────────────────────────────────────────────────────────────
const TABS = {
  PG_RATES:      { tab: 'PG_RATES',      headerRow: 3, dataStartRow: 4 },
  ISSUER_BLOCKS: { tab: 'ISSUER_BLOCKS', headerRow: 3, dataStartRow: 5 },
};

function rowsToObjects(headers, rows) {
  return rows
    .filter(row => row && row.some(v => v !== '' && v !== null && v !== undefined))
    .map((row, i) => {
      const obj = { _rowIndex: i };
      headers.forEach((h, hi) => { obj[h] = row[hi] ?? ''; });
      return obj;
    });
}

function checkAdmin(req, res) {
  if (req.headers['x-admin-pin'] !== ADMIN_PIN) {
    res.status(403).json({ error: 'Unauthorized' });
    return false;
  }
  return true;
}

function colLetter(n) {
  let r = '';
  while (n > 0) { n--; r = String.fromCharCode(65 + (n % 26)) + r; n = Math.floor(n / 26); }
  return r;
}

// ── GET /api/sheets — read all data ──────────────────────────────────────────
app.get('/api/sheets', async (req, res) => {
  try {
    const sheets  = await getSheetsClient();
    const results = {};
    const sheetParam = req.query.sheet;

    for (const [key, cfg] of Object.entries(TABS)) {
      if (sheetParam && sheetParam !== key) continue;

      const response = await sheets.spreadsheets.values.get({
        spreadsheetId: SHEET_ID,
        range: `${cfg.tab}!A${cfg.headerRow}:ZZ`,
      });

      const allRows    = response.data.values || [];
      const headers    = allRows[0] || [];
      const dataOffset = cfg.dataStartRow - cfg.headerRow;
      const dataRows   = allRows.slice(dataOffset);

      results[key] = { headers, rows: rowsToObjects(headers, dataRows) };
    }

    res.json({ ok: true, data: results });
  } catch (err) {
    console.error('GET /api/sheets error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── POST /api/sheets — add or update a row ───────────────────────────────────
app.post('/api/sheets', async (req, res) => {
  if (!checkAdmin(req, res)) return;
  const { sheet, rowIndex, values, action } = req.body;
  const cfg = TABS[sheet];
  if (!cfg) return res.status(400).json({ error: 'Unknown sheet' });

  try {
    const sheets = await getSheetsClient();

    if (action === 'add') {
      await sheets.spreadsheets.values.append({
        spreadsheetId: SHEET_ID,
        range: `${cfg.tab}!A${cfg.dataStartRow}`,
        valueInputOption: 'USER_ENTERED',
        insertDataOption: 'INSERT_ROWS',
        requestBody: { values: [values] },
      });
      return res.json({ ok: true, action: 'added' });
    }

    if (action === 'update') {
      const actualRow = cfg.dataStartRow + rowIndex;
      await sheets.spreadsheets.values.update({
        spreadsheetId: SHEET_ID,
        range: `${cfg.tab}!A${actualRow}`,
        valueInputOption: 'USER_ENTERED',
        requestBody: { values: [values] },
      });
      return res.json({ ok: true, action: 'updated', row: actualRow });
    }

    res.status(400).json({ error: 'Unknown action' });
  } catch (err) {
    console.error('POST /api/sheets error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── PUT /api/sheets — toggle STATUS only ─────────────────────────────────────
app.put('/api/sheets', async (req, res) => {
  if (!checkAdmin(req, res)) return;
  const { sheet, rowIndex, status } = req.body;
  const cfg = TABS[sheet];
  if (!cfg) return res.status(400).json({ error: 'Unknown sheet' });

  try {
    const sheets = await getSheetsClient();

    const hdrResp = await sheets.spreadsheets.values.get({
      spreadsheetId: SHEET_ID,
      range: `${cfg.tab}!A${cfg.headerRow}:ZZ${cfg.headerRow}`,
    });
    const headers   = hdrResp.data.values?.[0] || [];
    const statusCol = headers.indexOf('STATUS');
    if (statusCol === -1) return res.status(400).json({ error: 'STATUS column not found' });

    const actualRow = cfg.dataStartRow + rowIndex;
    await sheets.spreadsheets.values.update({
      spreadsheetId: SHEET_ID,
      range: `${cfg.tab}!${colLetter(statusCol + 1)}${actualRow}`,
      valueInputOption: 'USER_ENTERED',
      requestBody: { values: [[status]] },
    });

    res.json({ ok: true, status });
  } catch (err) {
    console.error('PUT /api/sheets error:', err.message);
    res.status(500).json({ error: err.message });
  }
});

// ── Health check ──────────────────────────────────────────────────────────────
app.get('/api/health', (req, res) => {
  res.json({ ok: true, ts: new Date().toISOString(), sheet: !!SHEET_ID });
});

// ── SPA fallback — serve index.html for all non-API routes ───────────────────
app.get('*', (req, res) => {
  res.sendFile(path.join(__dirname, '../public/index.html'));
});

// ── Start ─────────────────────────────────────────────────────────────────────
app.listen(PORT, '0.0.0.0', () => {
  console.log(`✓ PG Rate Portal running on http://0.0.0.0:${PORT}`);
  console.log(`  Sheet ID : ${SHEET_ID ? SHEET_ID.slice(0,12)+'...' : 'NOT SET'}`);
  console.log(`  Admin PIN: ${ADMIN_PIN}`);
});
