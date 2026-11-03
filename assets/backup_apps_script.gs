/**
 * @OnlyCurrentDoc
 * Penanda di atas membatasi izin skrip hanya pada Google Sheet tempat ia ditempel
 * (the script can only access this spreadsheet, not your other files).
 */

// RekapRapi - Backup ke Google Sheet / Backup to Google Sheets
//
// EN: Paste ALL of this code into your Google Sheet (Extensions > Apps Script), Save, then
// Deploy > New deployment > Web app (Execute as: Me, Who has access: Anyone) and copy the
// Web app URL (ending in /exec) into RekapRapi.
//
// Tempel SELURUH kode ini di Google Sheet Anda: menu Ekstensi > Apps Script, hapus isi
// yang ada, tempel, lalu simpan. Kemudian: Terapkan (Deploy) > Penerapan baru > jenis
// "Aplikasi web", "Jalankan sebagai: Saya", "Yang memiliki akses: Siapa saja", lalu
// salin URL aplikasi web ke RekapRapi (Laporan > Backup ke Google Sheet).
//
// Aman karena: setiap permintaan harus membawa KODE RAHASIA di bawah. Skrip ini hanya
// bisa menulis ke Google Sheet tempat ia ditempel, dan tidak mengirim data ke mana pun.

const TOKEN = '__KODE_RAHASIA__';

// Batas Google Sheets adalah 10 juta sel per spreadsheet; sisakan ruang untuk lembar lain.
const MAX_CELLS = 5000000;

// Dibuka dari browser untuk memeriksa bahwa penerapan berhasil.
function doGet() {
  return json_({ ok: true, app: 'RekapRapi Backup', message: 'Siap menerima backup.' });
}

function doPost(e) {
  try {
    const raw = e && e.postData && e.postData.contents;
    if (!raw) return json_({ ok: false, error: 'Tidak ada data.' });

    const body = JSON.parse(raw);
    if (!body || body.token !== TOKEN) {
      return json_({ ok: false, error: 'Kode rahasia tidak cocok.' });
    }

    const ss = SpreadsheetApp.getActiveSpreadsheet();
    if (body.ping) {
      return json_({ ok: true, ping: true, spreadsheetUrl: ss.getUrl() });
    }

    const sheets = body.sheets || [];
    let cells = 0;
    sheets.forEach(function (s) {
      const rows = s.rows || [];
      const cols = rows.reduce(function (m, r) { return Math.max(m, r.length); }, 0);
      cells += rows.length * cols;
    });
    if (cells > MAX_CELLS) {
      return json_({ ok: false, error: 'Data terlalu besar untuk satu spreadsheet (' + cells + ' sel).' });
    }

    // Satu backup pada satu waktu agar dua klik tidak saling menimpa.
    const lock = LockService.getScriptLock();
    lock.waitLock(30000);
    try {
      const counts = {};
      sheets.forEach(function (s) {
        counts[sheetName_(s.name)] = writeSheet_(ss, s);
      });
      SpreadsheetApp.flush();
      return json_({
        ok: true,
        spreadsheetUrl: ss.getUrl(),
        sheets: counts,
        at: new Date().toISOString(),
      });
    } finally {
      lock.releaseLock();
    }
  } catch (err) {
    return json_({ ok: false, error: String(err && err.message ? err.message : err) });
  }
}

function sheetName_(name) {
  const clean = String(name).replace(/[\[\]*?:\/\\]/g, ' ').trim().substring(0, 100);
  return clean || 'Data';
}

// Menimpa satu lembar dengan data terbaru. Baris pertama adalah judul kolom.
// Mengembalikan jumlah baris data (tanpa judul).
function writeSheet_(ss, spec) {
  const name = sheetName_(spec.name);
  const rows = spec.rows || [];
  const sh = ss.getSheetByName(name) || ss.insertSheet(name);
  sh.clear();
  if (rows.length === 0) return 0;

  const cols = rows.reduce(function (m, r) { return Math.max(m, r.length); }, 0);
  if (cols === 0) return 0;
  const grid = rows.map(function (r) {
    const c = r.slice();
    while (c.length < cols) c.push('');
    return c;
  });

  // Perbesar lembar bila perlu; menulis di luar ukuran lembar menimbulkan galat.
  if (sh.getMaxRows() < grid.length) {
    sh.insertRowsAfter(sh.getMaxRows(), grid.length - sh.getMaxRows());
  }
  if (sh.getMaxColumns() < cols) {
    sh.insertColumnsAfter(sh.getMaxColumns(), cols - sh.getMaxColumns());
  }

  // Kolom teks (nama, catatan, telepon) dipaksa berupa teks agar nomor berawalan 0
  // tidak kehilangan angka nol dan isi berawalan "=" tidak dijalankan sebagai rumus.
  (spec.textColumns || []).forEach(function (c) {
    if (c >= 0 && c < cols) {
      sh.getRange(1, c + 1, grid.length, 1).setNumberFormat('@');
    }
  });

  sh.getRange(1, 1, grid.length, cols).setValues(grid);
  sh.setFrozenRows(1);
  sh.getRange(1, 1, 1, cols).setFontWeight('bold');
  if (grid.length <= 1000) sh.autoResizeColumns(1, cols);
  return grid.length - 1;
}

function json_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}
