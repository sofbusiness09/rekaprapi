// Menjalankan assets/backup_apps_script.gs terhadap tiruan Google Sheet yang meniru
// aturan nyata: menulis di luar ukuran lembar adalah galat, kolom berformat '@' menyimpan teks.
'use strict';
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');

const scriptPath = process.argv[2];
const payloadPath = process.argv[3]; // opsional: payload nyata dari aplikasi
const TOKEN = 'abcdef0123456789abcdef0123456789';

function makeEnv() {
  const store = { sheets: new Map(), flushed: 0, lockHeld: false };

  class Sheet {
    constructor(name) { this.name = name; this.maxRows = 1000; this.maxCols = 26; this.reset(); }
    reset() { this.cells = new Map(); this.textCols = new Set(); this.frozen = 0; this.boldRow = false; }
    clear() { this.reset(); return this; }
    getMaxRows() { return this.maxRows; }
    getMaxColumns() { return this.maxCols; }
    insertRowsAfter(after, n) { assert(after === this.maxRows); this.maxRows += n; }
    insertColumnsAfter(after, n) { assert(after === this.maxCols); this.maxCols += n; }
    setFrozenRows(n) { this.frozen = n; }
    autoResizeColumns() {}
    getRange(r, c, nr = 1, nc = 1) {
      const sheet = this;
      if (r < 1 || c < 1 || r + nr - 1 > this.maxRows || c + nc - 1 > this.maxCols) {
        throw new Error('The coordinates of the range are outside the dimensions of the sheet.');
      }
      return {
        setNumberFormat(fmt) { if (fmt === '@') for (let i = 0; i < nc; i++) sheet.textCols.add(c + i); return this; },
        setFontWeight(w) { if (r === 1 && w === 'bold') sheet.boldRow = true; return this; },
        setValues(v) {
          assert.strictEqual(v.length, nr, 'jumlah baris tidak sama');
          v.forEach((row, i) => {
            assert.strictEqual(row.length, nc, 'jumlah kolom tidak sama pada baris ' + i);
            row.forEach((val, j) => {
              const col = c + j;
              sheet.cells.set((r + i) + ',' + col, sheet.textCols.has(col) ? String(val) : val);
            });
          });
          return this;
        },
      };
    }
    value(r, c) { return this.cells.get(r + ',' + c); }
    get lastRow() { let m = 0; for (const k of this.cells.keys()) m = Math.max(m, +k.split(',')[0]); return m; }
  }

  const ss = {
    getSheetByName: (n) => store.sheets.get(n) || null,
    insertSheet: (n) => { const s = new Sheet(n); store.sheets.set(n, s); return s; },
    getUrl: () => 'https://docs.google.com/spreadsheets/d/FAKE_ID/edit',
  };
  const out = (s) => ({ content: s, setMimeType() { return this; } });
  const sandbox = {
    SpreadsheetApp: { getActiveSpreadsheet: () => ss, flush: () => { store.flushed++; } },
    ContentService: { createTextOutput: out, MimeType: { JSON: 'json' } },
    LockService: {
      getScriptLock: () => ({
        waitLock() { assert(!store.lockHeld, 'kunci sudah dipegang'); store.lockHeld = true; },
        releaseLock() { store.lockHeld = false; },
      }),
    },
    console,
  };
  return { store, sandbox };
}

function load() {
  const { store, sandbox } = makeEnv();
  const code = fs.readFileSync(scriptPath, 'utf8').replace('__KODE_RAHASIA__', TOKEN);
  vm.createContext(sandbox);
  vm.runInContext(code + '\n;this.doPost = doPost; this.doGet = doGet;', sandbox);
  return { store, post: (body) => JSON.parse(sandbox.doPost({ postData: { contents: typeof body === 'string' ? body : JSON.stringify(body) } }).content), get: () => JSON.parse(sandbox.doGet().content) };
}

let passed = 0;
function test(name, fn) { try { fn(); passed++; console.log('  ok   ' + name); } catch (e) { console.log('  GAGAL ' + name + '\n       ' + (e && e.stack || e)); process.exitCode = 1; } }

test('doGet menjawab siap', () => {
  const { get } = load();
  assert.strictEqual(get().ok, true);
});

test('token salah ditolak dan tidak menulis apa pun', () => {
  const { store, post } = load();
  const r = post({ token: 'salah', sheets: [{ name: 'Kas', rows: [['a']] }] });
  assert.strictEqual(r.ok, false);
  assert.strictEqual(store.sheets.size, 0);
});

test('tanpa data / JSON rusak menghasilkan galat rapi', () => {
  const { post } = load();
  assert.strictEqual(post('').ok, false);
  const r = post('{rusak');
  assert.strictEqual(r.ok, false);
  assert(r.error.length > 0);
});

test('ping mengembalikan alamat spreadsheet tanpa menulis', () => {
  const { store, post } = load();
  const r = post({ token: TOKEN, ping: true });
  assert.strictEqual(r.ok, true);
  assert(r.spreadsheetUrl.startsWith('https://docs.google.com/spreadsheets/'));
  assert.strictEqual(store.sheets.size, 0);
});

test('menulis lembar baru, judul dibekukan, hitung baris data', () => {
  const { store, post } = load();
  const r = post({ token: TOKEN, sheets: [
    { name: 'Kas', rows: [['Tanggal', 'Jumlah', 'Catatan'], ['2026-11-03', 1000, 'a'], ['2026-11-04', 2500, 'b']], textColumns: [2] },
  ] });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.sheets.Kas, 2);
  const sh = store.sheets.get('Kas');
  assert.strictEqual(sh.frozen, 1);
  assert.strictEqual(sh.boldRow, true);
  assert.strictEqual(sh.value(3, 2), 2500);
  assert(store.flushed >= 1);
  assert.strictEqual(store.lockHeld, false, 'kunci harus dilepas');
});

test('backup kedua menimpa isi lama (data terakhir), bukan menambah', () => {
  const { store, post } = load();
  post({ token: TOKEN, sheets: [{ name: 'Kas', rows: [['T', 'J'], ['a', 1], ['b', 2], ['c', 3]] }] });
  const r = post({ token: TOKEN, sheets: [{ name: 'Kas', rows: [['T', 'J'], ['z', 9]] }] });
  assert.strictEqual(r.sheets.Kas, 1);
  const sh = store.sheets.get('Kas');
  assert.strictEqual(sh.lastRow, 2, 'sisa baris lama harus hilang');
  assert.strictEqual(sh.value(2, 1), 'z');
  assert.strictEqual(sh.value(3, 1), undefined);
});

test('lembar yang lebih besar dari ukuran bawaan diperluas (baris dan kolom)', () => {
  const { store, post } = load();
  const rows = [Array.from({ length: 40 }, (_, i) => 'K' + i)];
  for (let i = 0; i < 1500; i++) rows.push(Array.from({ length: 40 }, (_, j) => i * 100 + j));
  const r = post({ token: TOKEN, sheets: [{ name: 'Besar', rows }] });
  assert.strictEqual(r.ok, true, JSON.stringify(r));
  assert.strictEqual(r.sheets.Besar, 1500);
  const sh = store.sheets.get('Besar');
  assert(sh.maxRows >= 1501 && sh.maxCols >= 40);
});

test('baris tidak rata dilengkapi, kolom teks tetap teks (nol di depan dan rumus aman)', () => {
  const { store, post } = load();
  const r = post({ token: TOKEN, sheets: [{
    name: 'Kontak',
    rows: [['Nama', 'Telepon', 'Catatan', 'Saldo'], ['Bu Evi', '0811223344', '=HYPERLINK("http://x")'], ['Pak Budi', '+62812', '', 5000]],
    textColumns: [0, 1, 2],
  }] });
  assert.strictEqual(r.ok, true, JSON.stringify(r));
  const sh = store.sheets.get('Kontak');
  assert.strictEqual(sh.value(2, 2), '0811223344');
  assert.strictEqual(sh.value(2, 3), '=HYPERLINK("http://x")', 'tersimpan sebagai teks, bukan rumus');
  assert.strictEqual(sh.value(2, 4), '', 'sel kosong dilengkapi');
  assert.strictEqual(sh.value(3, 4), 5000, 'angka tetap angka');
});

test('nama lembar dibersihkan dari karakter terlarang', () => {
  const { store, post } = load();
  const r = post({ token: TOKEN, sheets: [{ name: 'Kas/Bank [2026]?', rows: [['a'], ['b']] }] });
  assert.strictEqual(r.ok, true);
  assert([...store.sheets.keys()].every((n) => !/[\[\]*?:\/\\]/.test(n)));
});

test('lembar kosong tidak menimbulkan galat', () => {
  const { post } = load();
  const r = post({ token: TOKEN, sheets: [{ name: 'Kosong', rows: [] }, { name: 'JudulSaja', rows: [['A', 'B']] }] });
  assert.strictEqual(r.ok, true);
  assert.strictEqual(r.sheets.Kosong, 0);
  assert.strictEqual(r.sheets.JudulSaja, 0);
});

test('data melebihi batas sel ditolak sebelum menulis', () => {
  const { store, post } = load();
  const row = Array.from({ length: 100 }, () => 1);
  const rows = Array.from({ length: 60000 }, () => row); // 6 juta sel
  const r = post({ token: TOKEN, sheets: [{ name: 'Raksasa', rows }] });
  assert.strictEqual(r.ok, false);
  assert(/terlalu besar/i.test(r.error));
  assert.strictEqual(store.sheets.size, 0);
});

if (payloadPath) {
  test('payload nyata dari aplikasi tertulis lengkap', () => {
    const payload = JSON.parse(fs.readFileSync(payloadPath, 'utf8'));
    payload.token = TOKEN;
    const { store, post } = load();
    const r = post(payload);
    assert.strictEqual(r.ok, true, JSON.stringify(r));
    for (const s of payload.sheets) {
      const sh = store.sheets.get(s.name.replace(/[\[\]*?:\/\\]/g, ' ').trim().substring(0, 100));
      assert(sh, 'lembar ' + s.name + ' tidak ada');
      assert.strictEqual(r.sheets[s.name], Math.max(0, s.rows.length - 1), 'jumlah baris ' + s.name);
      // Setiap nilai teks pada kolom teks harus sama persis dengan yang dikirim.
      (s.textColumns || []).forEach((c) => {
        s.rows.forEach((row, i) => { if (row[c] !== undefined) assert.strictEqual(sh.value(i + 1, c + 1), String(row[c]), s.name + ' baris ' + (i + 1) + ' kolom ' + c); });
      });
      // Kolom angka tetap angka.
      s.rows.slice(1).forEach((row, i) => row.forEach((v, c) => {
        if (typeof v === 'number' && !(s.textColumns || []).includes(c)) assert.strictEqual(sh.value(i + 2, c + 1), v);
      }));
    }
    // Backup ulang dengan data yang sama menghasilkan keadaan yang sama (idempoten).
    const again = post(payload);
    assert.strictEqual(again.ok, true);
    assert.deepStrictEqual(again.sheets, r.sheets);
  });
}

console.log('\n' + passed + ' lulus' + (process.exitCode ? ', ada yang gagal' : ''));
