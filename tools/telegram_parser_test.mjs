// Tes pembaca pesan dan pintu masuk bot Telegram (tanpa jaringan sungguhan).
// Jalankan: node tools/telegram_parser_test.mjs
import assert from 'node:assert/strict';

// Lingkungan tiruan Deno dan fetch, dipasang sebelum modul dimuat.
const calls = [];
const envs = {
  TELEGRAM_BOT_TOKEN: 'TOKEN',
  TELEGRAM_WEBHOOK_SECRET: 'rahasia',
  SUPABASE_URL: 'https://x.supabase.co',
  SUPABASE_SERVICE_ROLE_KEY: 'svc',
};
let served = false;
globalThis.Deno = { env: { get: (k) => envs[k] }, serve: () => { served = true; } };
let rpcResults = {};
globalThis.fetch = async (url, init) => {
  const body = JSON.parse(init.body);
  if (url.includes('api.telegram.org')) {
    const method = url.split('/').pop();
    calls.push({ tg: method, body });
    return { ok: true, json: async () => ({ ok: true, result: { username: 'UjiBot' } }) };
  }
  const fn = url.split('/rpc/')[1];
  calls.push({ rpc: fn, body, auth: init.headers.Authorization });
  const out = typeof rpcResults[fn] === 'function' ? rpcResults[fn](body) : rpcResults[fn];
  return { ok: true, text: async () => JSON.stringify(out ?? null) };
};

const { parseAmount, parseEntry, rupiah, describe, handle } = await import(
  '../supabase/functions/telegram-bot/index.ts'
);

let passed = 0;
async function test(name, fn) {
  try {
    await fn();
    passed++;
    console.log('  ok   ' + name);
  } catch (e) {
    console.log('  GAGAL ' + name + '\n       ' + (e.stack ?? e));
    process.exitCode = 1;
  }
}

await test('jumlah: berbagai cara menulis', () => {
  const cases = {
    '50000': 50000, '50.000': 50000, '50,000': 50000, '1.250.000': 1250000,
    '50rb': 50000, '50RB': 50000, '50ribu': 50000, '50k': 50000,
    '1,5jt': 1500000, '1.5jt': 1500000, '2juta': 2000000, 'rp50.000': 50000,
    'Rp.25rb': 25000, '1.500rb': 1500000,
  };
  for (const [k, v] of Object.entries(cases)) assert.equal(parseAmount(k), v, k);
});

await test('jumlah: yang bukan jumlah ditolak', () => {
  for (const s of ['0', 'abc', '50x', '-5', '1.5', '12,5', '', 'rb', '9999999999999']) {
    assert.equal(parseAmount(s), null, s);
  }
});

await test('penjualan dengan modal dan catatan', () => {
  assert.deepEqual(parseEntry('jual 50000 modal 30000 kopi susu'),
    { ok: true, kind: 'sale', amount: 50000, cost: 30000, note: 'kopi susu' });
  assert.deepEqual(parseEntry('Jual 50 rb m 30 rb'),
    { ok: true, kind: 'sale', amount: 50000, cost: 30000 });
  assert.deepEqual(parseEntry('/jual 1,5jt modal 1jt'),
    { ok: true, kind: 'sale', amount: 1500000, cost: 1000000 });
});

await test('penjualan tanpa modal diminta melengkapi', () => {
  assert.deepEqual(parseEntry('jual 50000'), { ok: false, error: 'cost' });
  assert.deepEqual(parseEntry('jual 50000 modal'), { ok: false, error: 'cost' });
  assert.deepEqual(parseEntry('jual 50000 kopi'), { ok: false, error: 'cost' });
});

await test('pemasukan dan pengeluaran', () => {
  assert.deepEqual(parseEntry('masuk 25rb titipan'),
    { ok: true, kind: 'income', amount: 25000, note: 'titipan' });
  assert.deepEqual(parseEntry('keluar 20.000 listrik & air'),
    { ok: true, kind: 'expense', amount: 20000, note: 'listrik & air' });
  assert.deepEqual(parseEntry('  BAYAR   15000  '), { ok: true, kind: 'expense', amount: 15000 });
  assert.deepEqual(parseEntry('+ 5000'), { ok: true, kind: 'income', amount: 5000 });
});

await test('pesan tidak dikenal dan jumlah salah', () => {
  assert.deepEqual(parseEntry('halo'), { ok: false, error: 'unknown' });
  assert.deepEqual(parseEntry(''), { ok: false, error: 'unknown' });
  assert.deepEqual(parseEntry('keluar banyak'), { ok: false, error: 'amount' });
  assert.deepEqual(parseEntry('masuk'), { ok: false, error: 'amount' });
});

await test('rupiah dan isi konfirmasi; staf tidak melihat keuntungan', () => {
  assert.equal(rupiah(1250000), 'Rp1.250.000');
  const e = { kind: 'sale', amount: 50000, cost: 30000, note: 'a<b' };
  const owner = describe(e, { name: 'Toko & Co', role: 'owner' });
  assert.match(owner, /Keuntungan: Rp20\.000/);
  assert.match(owner, /Toko &amp; Co/);
  assert.match(owner, /a&lt;b/);
  assert.doesNotMatch(describe(e, { name: 'T', role: 'staff' }), /Keuntungan/);
  assert.match(describe({ kind: 'sale', amount: 10, cost: 30 }, { name: 'T', role: 'admin' }), /Kerugian: Rp20/);
});

const post = (update, secret = 'rahasia') => handle(new Request('https://f/telegram-bot', {
  method: 'POST',
  headers: { 'X-Telegram-Bot-Api-Secret-Token': secret, 'Content-Type': 'application/json' },
  body: JSON.stringify(update),
}));
const msg = (text, type = 'private') => ({
  message: { chat: { id: 9, type }, from: { id: 7, first_name: 'Ani' }, text },
});

await test('modul dimuat dan mendaftarkan server', () => assert.equal(served, true));

await test('tanpa kepala rahasia Telegram ditolak', async () => {
  calls.length = 0;
  const res = await post(msg('keluar 1000'), 'salah');
  assert.equal(res.status, 403);
  assert.equal(calls.length, 0);
});

await test('GET tanpa kunci setup tidak memasang apa pun', async () => {
  calls.length = 0;
  const res = await handle(new Request('https://f/telegram-bot?setup=tebak'));
  assert.equal(res.status, 200);
  assert.equal(calls.length, 0);
});

await test('setup mendaftarkan webhook dan menyimpan nama bot', async () => {
  calls.length = 0;
  const res = await handle(new Request('https://f/telegram-bot?setup=rahasia'));
  assert.deepEqual(await res.json(),
    { ok: true, webhook: null, bot: 'UjiBot', telegram: 'ok', database: 'ok' });
  const hook = calls.find((c) => c.tg === 'setWebhook');
  assert.equal(hook.body.url, 'https://x.supabase.co/functions/v1/telegram-bot');
  assert.equal(hook.body.secret_token, 'rahasia');
  assert.deepEqual(calls.find((c) => c.rpc === 'tg_set_bot').body, { p_username: 'UjiBot' });
});

await test('akun yang belum terhubung tidak bisa mencatat', async () => {
  calls.length = 0;
  rpcResults = { tg_context: { linked: false } };
  await post(msg('keluar 1000'));
  assert.ok(!calls.some((c) => c.rpc === 'tg_set_pending' || c.rpc === 'tg_record'));
  assert.match(calls.find((c) => c.tg === 'sendMessage').body.text, /belum terhubung/);
});

await test('grup ditolak sebelum menyentuh data', async () => {
  calls.length = 0;
  await post(msg('keluar 1000', 'group'));
  assert.ok(!calls.some((c) => c.rpc));
});

await test('/start KODE menghubungkan dengan id pengirim', async () => {
  calls.length = 0;
  rpcResults = { tg_link: { ok: true, business: 'Toko' } };
  await post(msg('/start abc123'));
  assert.deepEqual(calls.find((c) => c.rpc === 'tg_link').body,
    { p_code: 'abc123', p_tg_id: 7, p_chat_id: 9, p_name: 'Ani' });
});

const linked = { linked: true, business: { id: 'b1', name: 'Toko', kind: 'business', role: 'owner' }, businesses: [] };

await test('catatan menunggu konfirmasi, belum disimpan', async () => {
  calls.length = 0;
  rpcResults = { tg_context: linked };
  await post(msg('jual 50000 modal 30000'));
  const pend = calls.find((c) => c.rpc === 'tg_set_pending').body;
  assert.equal(pend.p_tg_id, 7);
  assert.equal(pend.p_payload.amount, 50000);
  assert.ok(!calls.some((c) => c.rpc === 'tg_record'));
  const sent = calls.find((c) => c.tg === 'sendMessage').body;
  assert.equal(sent.reply_markup.inline_keyboard[0][0].callback_data, 'ok:' + pend.p_payload.n);
});

await test('penjualan ditolak di Pembukuan Pribadi', async () => {
  calls.length = 0;
  rpcResults = { tg_context: { ...linked, business: { ...linked.business, kind: 'personal' } } };
  await post(msg('jual 50000 modal 30000'));
  assert.ok(!calls.some((c) => c.rpc === 'tg_set_pending'));
});

const cb = (data) => ({
  callback_query: { id: 'q', from: { id: 7 }, data, message: { chat: { id: 9 }, message_id: 3 } },
});

await test('Simpan menyimpan tepat yang dikonfirmasi', async () => {
  calls.length = 0;
  const pending = { n: 'n1', kind: 'expense', amount: 20000, note: 'listrik' };
  rpcResults = { tg_take_pending: pending, tg_record: { ok: true, business: 'Toko', category: 'Listrik & Air' }, tg_context: linked };
  await post(cb('ok:n1'));
  assert.deepEqual(calls.find((c) => c.rpc === 'tg_take_pending').body, { p_tg_id: 7, p_nonce: 'n1' });
  assert.deepEqual(calls.find((c) => c.rpc === 'tg_record').body, { p_tg_id: 7, p_payload: pending });
  assert.match(calls.find((c) => c.tg === 'editMessageText').body.text, /Tersimpan[\s\S]*Listrik &amp; Air/);
});

await test('tombol lama atau Batal tidak menyimpan', async () => {
  calls.length = 0;
  rpcResults = { tg_take_pending: null };
  await post(cb('ok:lama'));
  assert.ok(!calls.some((c) => c.rpc === 'tg_record'));
  calls.length = 0;
  rpcResults = { tg_take_pending: { n: 'n2', kind: 'expense', amount: 1 } };
  await post(cb('no:n2'));
  assert.ok(!calls.some((c) => c.rpc === 'tg_record'));
});

await test('galat di tengah tetap dijawab 200', async () => {
  rpcResults = { tg_context: () => { throw new Error('putus'); } };
  const res = await post(msg('keluar 1000'));
  assert.equal(res.status, 200);
});

console.log(`\n${passed} lulus${process.exitCode ? ', ada yang gagal' : ''}`);
