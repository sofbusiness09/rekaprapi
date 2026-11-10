// RekapRapi: Bot Telegram (Supabase Edge Function).
//
// Satu berkas tanpa pustaka luar, supaya bisa ditempel langsung di dasbor Supabase.
// Rahasia yang harus diisi di Edge Functions > Secrets:
//   TELEGRAM_BOT_TOKEN       token dari @BotFather
//   TELEGRAM_WEBHOOK_SECRET  teks acak buatan sendiri (huruf, angka, _ atau -)
// SUPABASE_URL dan SUPABASE_SERVICE_ROLE_KEY sudah tersedia otomatis.
//
// Setelah dipasang, buka sekali di peramban:
//   https://<proyek>.supabase.co/functions/v1/telegram-bot?setup=<TELEGRAM_WEBHOOK_SECRET>
// Itu mendaftarkan alamat ini ke Telegram dan menyimpan nama bot untuk aplikasi.
//
// Fungsi ini harus dipasang dengan "Verify JWT" DIMATIKAN: Telegram tidak mengirim JWT.
// Keasliannya diperiksa lewat kepala X-Telegram-Bot-Api-Secret-Token.

declare const Deno: any;

// ---------------------------------------------------------------------------
// Pembaca pesan (tanpa jaringan; diuji di tools/telegram_parser_test.mjs)
// ---------------------------------------------------------------------------

const SUFFIX: Record<string, number> = {
  rb: 1e3,
  ribu: 1e3,
  k: 1e3,
  jt: 1e6,
  juta: 1e6,
};
const MAX_AMOUNT = 1e12;

/** "50000", "50.000", "rp50rb", "1,5jt" -> rupiah bulat; null bila bukan jumlah. */
export function parseAmount(raw: string): number | null {
  const s = raw.toLowerCase().replace(/^rp\.?/, "");
  const m = /^(\d[\d.,]*)(rb|ribu|k|jt|juta)?$/.exec(s);
  if (!m) return null;
  const digits = m[1];
  const grouped = /^\d{1,3}([.,]\d{3})+$/.test(digits);
  let value: number;
  if (m[2]) {
    const n = grouped
      ? Number(digits.replace(/[.,]/g, ""))
      : Number(digits.replace(",", "."));
    if (!Number.isFinite(n)) return null;
    value = Math.round(n * SUFFIX[m[2]]);
  } else if (/^\d+$/.test(digits)) {
    value = Number(digits);
  } else if (grouped) {
    value = Number(digits.replace(/[.,]/g, ""));
  } else {
    return null;
  }
  return value > 0 && value <= MAX_AMOUNT ? value : null;
}

/** Membaca jumlah di tokens[i]; "50 rb" (dua kata) juga diterima. */
function readAmount(tokens: string[], i: number): [number, number] | null {
  if (i >= tokens.length) return null;
  const next = tokens[i + 1]?.toLowerCase();
  if (next && next in SUFFIX) {
    const joined = parseAmount(tokens[i] + next);
    if (joined != null) return [joined, i + 2];
  }
  const single = parseAmount(tokens[i]);
  return single == null ? null : [single, i + 1];
}

export type Kind = "sale" | "income" | "expense" | "receivable" | "payable" | "settle";

export type Entry =
  | { ok: true; kind: Kind; amount: number; cost?: number; note?: string; contact?: string }
  | { ok: false; error: "unknown" | "amount" | "cost" | "contact" };

const SALE = ["jual", "penjualan", "j"];
const INCOME = ["masuk", "pemasukan", "terima", "+"];
const EXPENSE = ["keluar", "pengeluaran", "bayar", "beli", "-"];
const RECEIVABLE = ["piutang"];
const PAYABLE = ["utang", "hutang"];
/** Pelunasan: "lunas Budi" (seluruh sisa) atau "cicil 50000 Budi". Jumlah 0 = seluruh sisa. */
const SETTLE = ["lunas", "pelunasan", "lunasi", "cicil", "cicilan"];
/** Kata penanda penjualan utang: "jual 50000 modal 30000 utang Budi". */
const CREDIT = ["utang", "hutang", "kredit", "piutang"];

/** "Budi Santoso, pinjam modal" -> nama kontak dan catatan (setelah koma). */
function splitContact(rest: string): { contact: string; note: string } {
  const comma = rest.indexOf(",");
  const contact = (comma < 0 ? rest : rest.slice(0, comma)).trim().slice(0, 60);
  const note = comma < 0 ? "" : rest.slice(comma + 1).trim().slice(0, 200);
  return { contact, note };
}

/**
 * jual 50000 modal 30000 kopi          -> penjualan lunas
 * jual 50000 modal 30000 utang Budi    -> penjualan utang (piutang ke Budi)
 * masuk 25rb titipan                   -> pemasukan lain
 * keluar 20000 listrik                 -> pengeluaran
 * piutang 100000 Budi, pinjam modal    -> meminjamkan uang ke Budi
 * utang 100000 Budi                    -> menerima pinjaman uang dari Budi
 */
export function parseEntry(text: string): Entry {
  const tokens = text.trim().split(/\s+/).filter((t) => t.length > 0);
  if (tokens.length === 0) return { ok: false, error: "unknown" };
  const word = tokens[0].toLowerCase().replace(/^\//, "");
  const kind: Kind | null = SALE.includes(word)
    ? "sale"
    : INCOME.includes(word)
    ? "income"
    : EXPENSE.includes(word)
    ? "expense"
    : RECEIVABLE.includes(word)
    ? "receivable"
    : PAYABLE.includes(word)
    ? "payable"
    : SETTLE.includes(word)
    ? "settle"
    : null;
  if (!kind) return { ok: false, error: "unknown" };

  if (kind === "settle") {
    // Jumlah boleh tidak ditulis: berarti melunasi seluruh sisa.
    const amt = readAmount(tokens, 1);
    if (!amt && word.startsWith("cicil")) return { ok: false, error: "amount" };
    const parts = splitContact(tokens.slice(amt ? amt[1] : 1).join(" "));
    if (!parts.contact) return { ok: false, error: "contact" };
    return {
      ok: true,
      kind,
      amount: amt ? amt[0] : 0,
      ...(parts.note ? { note: parts.note } : {}),
      contact: parts.contact,
    };
  }
  const a = readAmount(tokens, 1);
  if (!a) return { ok: false, error: "amount" };
  let [amount, i] = a;
  let cost: number | undefined;
  if (kind === "sale") {
    const w = tokens[i]?.toLowerCase();
    if (w !== "modal" && w !== "m") return { ok: false, error: "cost" };
    const c = readAmount(tokens, i + 1);
    if (!c) return { ok: false, error: "cost" };
    [cost, i] = c;
  }

  let contact: string | undefined;
  let note: string;
  const credit = kind === "sale" && CREDIT.includes(tokens[i]?.toLowerCase() ?? "");
  if (kind === "receivable" || kind === "payable" || credit) {
    const parts = splitContact(tokens.slice(credit ? i + 1 : i).join(" "));
    if (!parts.contact) return { ok: false, error: "contact" };
    contact = parts.contact;
    note = parts.note;
  } else {
    note = tokens.slice(i).join(" ").slice(0, 200);
  }
  return {
    ok: true,
    kind,
    amount,
    ...(cost != null ? { cost } : {}),
    ...(note ? { note } : {}),
    ...(contact ? { contact } : {}),
  };
}
export function rupiah(n: number): string {
  const s = Math.abs(Math.round(n)).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return (n < 0 ? "-Rp" : "Rp") + s;
}

export function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

const KIND_LABEL: Record<string, string> = {
  sale: "Penjualan",
  income: "Pemasukan",
  expense: "Pengeluaran",
  receivable: "Piutang (meminjamkan uang)",
  payable: "Utang (menerima pinjaman)",
};

type Biz = { name: string; kind?: string; role: string };

function canSeeProfit(b: Biz): boolean {
  return b.role === "owner" || b.role === "admin";
}

/** Isi pesan konfirmasi. Keuntungan hanya untuk Pemilik dan Admin. */
export function describe(
  e: {
    kind: string;
    amount: number;
    cost?: number;
    note?: string;
    contact?: string;
    nc?: boolean;
    net?: number;
  },
  business: Biz,
): string {
  if (e.kind === "settle") {
    // net > 0: kontak berutang, uang diterima. net < 0: pengguna berutang, uang dibayarkan.
    const receive = (e.net ?? 0) > 0;
    const left = Math.abs(e.net ?? 0) - e.amount;
    const lines = [
      `<b>${receive ? "Terima pembayaran piutang" : "Bayar utang"}</b> · ${esc(business.name)}`,
      `${receive ? "Dari" : "Kepada"}: ${esc(e.contact ?? "")}`,
      `Jumlah: ${rupiah(e.amount)}`,
      left > 0 ? `Sisa setelah ini: ${rupiah(left)}` : "Setelah ini lunas",
    ];
    if (e.note) lines.push(`Catatan: ${esc(e.note)}`);
    return lines.join("\n");
  }
  const label = e.kind === "sale" && e.contact ? "Penjualan utang" : KIND_LABEL[e.kind];
  const lines = [`<b>${label}</b> · ${esc(business.name)}`, `Jumlah: ${rupiah(e.amount)}`];
  if (e.kind === "sale" && e.cost != null) {
    lines.push(`Modal: ${rupiah(e.cost)}`);
    if (canSeeProfit(business)) {
      const p = e.amount - e.cost;
      lines.push(`${p >= 0 ? "Keuntungan" : "Kerugian"}: ${rupiah(Math.abs(p))}`);
    }
  }
  if (e.contact) lines.push(`Kontak: ${esc(e.contact)}${e.nc ? " (kontak baru)" : ""}`);
  if (e.note) lines.push(`Catatan: ${esc(e.note)}`);
  return lines.join("\n");
}

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "Mei", "Jun", "Jul", "Agu", "Sep", "Okt", "Nov", "Des"];

/** "2026-11-12" -> "12 Nov". */
export function shortDate(iso: string): string {
  const [, m, d] = iso.split("-").map(Number);
  return `${d} ${MONTHS[m - 1]}`;
}

/** Ringkasan satu periode. Staf hanya melihat Pemasukan, Piutang, dan Utang. */
export function formatReport(title: string, business: Biz, s: Record<string, number>): string {
  const lines = [`<b>${title}</b> · ${esc(business.name)}`];
  if (business.kind === "personal") {
    lines.push(`Masuk: ${rupiah(s.total_in ?? 0)}`, `Keluar: ${rupiah(s.total_out ?? 0)}`);
    lines.push(`Saldo kas: ${rupiah(s.balance ?? 0)}`);
  } else {
    lines.push(`Pemasukan: ${rupiah(s.income_total ?? 0)}`);
    if (canSeeProfit(business) && s.net != null) {
      lines.push(`Pengeluaran: ${rupiah(s.expense_total ?? 0)}`);
      lines.push(`${s.net >= 0 ? "Laba" : "Rugi"}: ${rupiah(Math.abs(s.net))}`);
    }
  }
  lines.push(`Piutang belum lunas: ${rupiah(s.receivable_open ?? 0)}`);
  lines.push(`Utang belum lunas: ${rupiah(s.payable_open ?? 0)}`);
  return lines.join("\n");
}

type Due = { name: string; kind: string; remaining: number; due_date: string };

export function formatDue(due: Due[], today: string): string {
  if (!due?.length) return "";
  const lines = ["", "<b>Jatuh tempo</b>"];
  for (const d of due) {
    const late = d.due_date < today ? " (lewat tempo)" : "";
    const what = d.kind === "receivable" ? "piutang" : "utang";
    lines.push(`• ${esc(d.name)}: ${what} ${rupiah(d.remaining)}, ${shortDate(d.due_date)}${late}`);
  }
  return lines.join("\n");
}

/** Jawaban /utang: total, saldo per kontak, dan yang jatuh tempo. */
export function formatDebts(r: any): string {
  const lines = [
    `<b>Utang piutang</b> · ${esc(r.business.name)}`,
    `Piutang belum lunas: ${rupiah(r.receivable_open)}`,
    `Utang belum lunas: ${rupiah(r.payable_open)}`,
  ];
  const contacts = (r.contacts ?? []) as { name: string; net: number }[];
  if (contacts.length) {
    lines.push("", "<b>Per kontak</b>");
    for (const c of contacts) {
      lines.push(`• ${esc(c.name)}: ${c.net > 0 ? "piutang" : "utang"} ${rupiah(Math.abs(c.net))}`);
    }
  }
  return lines.join("\n") + formatDue(r.due ?? [], r.today);
}

export const HELP = [
  "<b>Cara mencatat</b>",
  "<code>jual 50000 modal 30000 kopi</code>",
  "<code>jual 50000 modal 30000 utang Budi</code>",
  "<code>masuk 25rb titipan</code>",
  "<code>keluar 20000 listrik</code>",
  "<code>piutang 100000 Budi</code>  meminjamkan uang",
  "<code>utang 100000 Budi</code>  menerima pinjaman",
  "<code>cicil 50000 Budi</code>  pembayaran sebagian",
  "<code>lunas Budi</code>  melunasi seluruh sisa",
  "",
  "Jumlah boleh ditulis 50000, 50.000, 50rb, atau 1,5jt. Catatan untuk utang piutang ditulis setelah koma. Setiap catatan dikonfirmasi dulu sebelum disimpan.",
  "",
  "/hari_ini  ringkasan hari ini",
  "/bulan_ini  ringkasan bulan ini",
  "/utang  utang piutang dan jatuh tempo",
  "/pembukuan  pindah pembukuan",
  "/batal  hapus catatan terakhir dari bot",
  "/laporan  hidupkan atau matikan ringkasan harian",
  "/putuskan  putuskan Telegram ini",
].join("\n");
const NOT_LINKED =
  "Telegram ini belum terhubung. Buka aplikasi RekapRapi, masuk ke Pengaturan > Telegram, lalu tekan Hubungkan.";

// ---------------------------------------------------------------------------
// Jaringan
// ---------------------------------------------------------------------------

function env(name: string): string {
  return Deno.env.get(name) ?? "";
}

async function tg(method: string, body: unknown): Promise<any> {
  const res = await fetch(`https://api.telegram.org/bot${env("TELEGRAM_BOT_TOKEN")}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  const json = await res.json().catch(() => ({}));
  if (!json.ok) console.error("telegram", method, json.description ?? res.status);
  return json;
}

async function rpc(fn: string, params: Record<string, unknown>): Promise<any> {
  const key = env("SUPABASE_SERVICE_ROLE_KEY") || env("SB_SECRET_KEY");
  const res = await fetch(`${env("SUPABASE_URL")}/rest/v1/rpc/${fn}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", apikey: key, Authorization: `Bearer ${key}` },
    body: JSON.stringify(params),
  });
  if (!res.ok) throw new Error(`rpc ${fn}: ${res.status} ${await res.text()}`);
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

function send(chat: number, text: string, extra: Record<string, unknown> = {}) {
  return tg("sendMessage", { chat_id: chat, text, parse_mode: "HTML", ...extra });
}

function edit(chat: number, message: number, text: string) {
  return tg("editMessageText", { chat_id: chat, message_id: message, text, parse_mode: "HTML" });
}

// ---------------------------------------------------------------------------
// Penanganan pesan
// ---------------------------------------------------------------------------

async function onMessage(msg: any) {
  const chat: number = msg.chat.id;
  const from: number = msg.from?.id;
  const text: string = (msg.text ?? "").trim();
  if (!from) return;
  // Hanya chat pribadi, agar isi pembukuan tidak muncul di grup.
  if (msg.chat.type !== "private") {
    await send(chat, "Bot ini hanya bisa dipakai lewat chat pribadi.");
    return;
  }
  if (!text) return;

  if (text.startsWith("/start")) {
    const code = text.split(/\s+/)[1];
    if (code) {
      const name = [msg.from.first_name, msg.from.last_name].filter(Boolean).join(" ");
      const r = await rpc("tg_link", { p_code: code, p_tg_id: from, p_chat_id: chat, p_name: name });
      if (r?.ok) {
        await send(chat, `Terhubung ke pembukuan <b>${esc(r.business)}</b>.\n\n${HELP}`);
      } else {
        await send(chat, "Kode tidak berlaku atau sudah kedaluwarsa. Buat kode baru dari Pengaturan > Telegram di aplikasi.");
      }
      return;
    }
  }

  const ctx = await rpc("tg_context", { p_tg_id: from });
  if (!ctx?.linked) {
    await send(chat, NOT_LINKED);
    return;
  }
  const business = ctx.business as { id: string; name: string; kind: string; role: string } | null;
  const command = text.split(/[\s@]/)[0].toLowerCase();

  if (command === "/start" || command === "/bantuan" || command === "/help") {
    const where = business ? `Pembukuan aktif: <b>${esc(business.name)}</b>\n\n` : "";
    await send(chat, where + HELP);
    return;
  }
  if (command === "/pembukuan") {
    const list = (ctx.businesses ?? []) as { id: string; name: string }[];
    if (list.length === 0) {
      await send(chat, "Anda belum punya pembukuan. Buat dulu di aplikasi.");
      return;
    }
    await send(chat, "Pilih pembukuan untuk dicatat:", {
      reply_markup: {
        inline_keyboard: list.map((b) => [{
          text: (b.id === business?.id ? "✓ " : "") + b.name,
          callback_data: `biz:${b.id}`,
        }]),
      },
    });
    return;
  }
  if (command === "/batal") {
    const r = await rpc("tg_undo", { p_tg_id: from });
    await send(
      chat,
      r?.ok
        ? `Catatan terakhir (${rupiah(r.amount)}) dihapus.`
        : "Tidak ada catatan dari bot dalam 30 menit terakhir yang bisa dihapus.",
    );
    return;
  }
  if (command === "/hari_ini" || command === "/bulan_ini") {
    const month = command === "/bulan_ini";
    const r = await rpc("tg_report", { p_tg_id: from, p_period: month ? "month" : "today" });
    await send(
      chat,
      r?.ok
        ? formatReport(month ? "Bulan ini" : "Hari ini", r.business, r.summary)
        : "Anda belum punya pembukuan. Buat dulu di aplikasi.",
    );
    return;
  }
  if (command === "/utang" && text.split(/\s+/).length === 1) {
    const r = await rpc("tg_debt_overview", { p_tg_id: from });
    await send(chat, r?.ok ? formatDebts(r) : "Anda belum punya pembukuan. Buat dulu di aplikasi.");
    return;
  }
  if (command === "/laporan") {
    const on = await rpc("tg_toggle_daily", { p_tg_id: from });
    await send(
      chat,
      on
        ? "Ringkasan harian dihidupkan. Dikirim sore hari bila ada catatan atau ada yang jatuh tempo."
        : "Ringkasan harian dimatikan.",
    );
    return;
  }
  if (command === "/putuskan") {
    await rpc("tg_unlink", { p_tg_id: from });
    await send(chat, "Telegram ini sudah diputuskan dari RekapRapi.");
    return;
  }

  const entry = parseEntry(text);
  if (!entry.ok) {
    const why = entry.error === "amount"
      ? "Jumlahnya tidak terbaca."
      : entry.error === "contact"
      ? "Nama kontaknya belum ada, contoh: <code>piutang 100000 Budi</code>."
      : entry.error === "cost"
      ? "Penjualan perlu modal, contoh: <code>jual 50000 modal 30000</code>. Tanpa modal, pakai <code>masuk 50000</code>."
      : "Pesan tidak dikenali.";
    await send(chat, `${why}\n\n${HELP}`);
    return;
  }
  if (!business) {
    await send(chat, "Anda belum punya pembukuan. Buat dulu di aplikasi.");
    return;
  }
  if (entry.kind === "sale" && business.kind !== "business") {
    await send(chat, "Pembukuan Pribadi tidak punya penjualan. Pakai <code>masuk</code> atau <code>keluar</code>.");
    return;
  }

  const nonce = crypto.randomUUID().slice(0, 8);

  if (entry.kind === "settle") {
    const bal = await rpc("tg_contact_balance", { p_tg_id: from, p_name: entry.contact });
    if (!bal?.found) {
      await send(chat, `Kontak "${esc(entry.contact ?? "")}" tidak ditemukan. Lihat daftarnya dengan /utang.`);
      return;
    }
    const net = Number(bal.net);
    if (net === 0) {
      await send(chat, `Tidak ada utang piutang yang belum lunas dengan ${esc(bal.name)}.`);
      return;
    }
    const amount = entry.amount || Math.abs(net);
    if (amount > Math.abs(net)) {
      await send(chat, `Jumlahnya melebihi sisa dengan ${esc(bal.name)}, yaitu ${rupiah(Math.abs(net))}.`);
      return;
    }
    const pending = { n: nonce, kind: "settle", amount, contact: bal.name as string, note: entry.note, net };
    await rpc("tg_set_pending", { p_tg_id: from, p_payload: pending });
    await send(chat, `${describe(pending, business)}\n\nSimpan catatan ini?`, {
      reply_markup: {
        inline_keyboard: [[
          { text: "✅ Simpan", callback_data: `ok:${nonce}` },
          { text: "Batal", callback_data: `no:${nonce}` },
        ]],
      },
    });
    return;
  }

  // Kontak yang sudah ada dipakai dengan ejaan tersimpan; yang belum ada dibuat saat disimpan.
  let contact = entry.contact;
  let nc = false;
  if (contact) {
    const found = await rpc("tg_find_contact", { p_tg_id: from, p_name: contact });
    if (found) contact = found as string;
    else nc = true;
  }
  const payload = {
    n: nonce,
    kind: entry.kind,
    amount: entry.amount,
    cost: entry.cost,
    note: entry.note,
    contact,
    nc: nc || undefined,
  };
  await rpc("tg_set_pending", { p_tg_id: from, p_payload: payload });
  await send(chat, `${describe(payload, business)}\n\nSimpan catatan ini?`, {
    reply_markup: {
      inline_keyboard: [[
        { text: "✅ Simpan", callback_data: `ok:${nonce}` },
        { text: "Batal", callback_data: `no:${nonce}` },
      ]],
    },
  });
}

async function onCallback(cb: any) {
  const from: number = cb.from.id;
  const chat: number | undefined = cb.message?.chat?.id;
  const message: number | undefined = cb.message?.message_id;
  const [action, value] = String(cb.data ?? "").split(":");
  await tg("answerCallbackQuery", { callback_query_id: cb.id });
  if (!chat || !message) return;

  if (action === "biz") {
    const ok = await rpc("tg_set_business", { p_tg_id: from, p_business: value });
    const ctx = ok ? await rpc("tg_context", { p_tg_id: from }) : null;
    await edit(
      chat,
      message,
      ctx?.business ? `Pembukuan aktif: <b>${esc(ctx.business.name)}</b>` : "Pembukuan itu tidak bisa dibuka.",
    );
    return;
  }

  if (action !== "ok" && action !== "no") return;
  const pending = await rpc("tg_take_pending", { p_tg_id: from, p_nonce: value });
  if (!pending) {
    await edit(chat, message, "Catatan ini sudah tidak berlaku. Kirim ulang bila masih perlu.");
    return;
  }
  if (action === "no") {
    await edit(chat, message, "Dibatalkan, tidak ada yang disimpan.");
    return;
  }
  if (pending.kind === "settle") {
    const s = await rpc("tg_settle", { p_tg_id: from, p_payload: pending });
    if (!s?.ok) {
      const why = s?.error === "over" || s?.error === "settled"
        ? "Sisa utang piutangnya sudah berubah. Periksa dengan /utang, lalu kirim ulang."
        : "Gagal menyimpan. Periksa akses Anda ke pembukuan ini, lalu coba lagi.";
      await edit(chat, message, why);
      return;
    }
    // Sisa dihitung dari jawaban database, bukan dari pratinjau.
    const net = (s.direction === "receive" ? 1 : -1) * (Number(s.amount) + Number(s.remaining));
    const done = describe({ ...pending, amount: Number(s.amount), contact: s.contact, net },
      { name: s.business, role: "staff" });
    await edit(chat, message, `✅ Tersimpan\n${done}\n\nSalah catat? Hapus pembayarannya dari aplikasi.`);
    return;
  }
  const r = await rpc("tg_record", { p_tg_id: from, p_payload: pending });
  if (!r?.ok) {
    await edit(chat, message, "Gagal menyimpan. Periksa akses Anda ke pembukuan ini, lalu coba lagi.");
    return;
  }
  const ctx = await rpc("tg_context", { p_tg_id: from });
  const body = describe({ ...pending, contact: r.contact ?? pending.contact, nc: r.new_contact },
    ctx?.business ?? { name: r.business, role: "staff" });
  const cat = r.category && pending.kind !== "sale" ? `\nKategori: ${esc(r.category)}` : "";
  await edit(chat, message, `✅ Tersimpan\n${body}${cat}\n\nSalah catat? Kirim /batal`);
}

// ---------------------------------------------------------------------------
// Pemasangan dan pintu masuk
// ---------------------------------------------------------------------------

/** Dipanggil penjadwal sekali sehari: ringkasan hari ini dan pengingat jatuh tempo. */
async function daily(): Promise<Response> {
  const rows = (await rpc("tg_daily_batch", {})) as any[];
  let sent = 0;
  for (const r of rows ?? []) {
    const text = formatReport("Ringkasan hari ini", r.business, r.summary) +
      formatDue(r.due ?? [], r.to) + "\n\nMatikan dengan /laporan";
    const res = await send(r.chat_id, text);
    if (res?.ok) sent++;
  }
  return Response.json({ ok: true, sent, total: rows?.length ?? 0 });
}

async function setup(): Promise<Response> {
  const url = `${env("SUPABASE_URL")}/functions/v1/telegram-bot`;
  const hook = await tg("setWebhook", {
    url,
    secret_token: env("TELEGRAM_WEBHOOK_SECRET"),
    allowed_updates: ["message", "callback_query"],
    drop_pending_updates: true,
  });
  const me = await tg("getMe", {});
  // Galat database dilaporkan apa adanya supaya penyebabnya terlihat saat memasang.
  let database = "ok";
  if (me?.ok) {
    const key = env("SUPABASE_SERVICE_ROLE_KEY") || env("SB_SECRET_KEY");
    if (!key) {
      database = "Kunci layanan tidak tersedia. Tambahkan rahasia SB_SECRET_KEY berisi kunci secret proyek.";
    } else {
      try {
        await rpc("tg_set_bot", { p_username: me.result.username });
      } catch (e) {
        database = String((e as Error)?.message ?? e).slice(0, 300);
      }
    }
  }
  await tg("setMyCommands", {
    commands: [
      { command: "bantuan", description: "Cara mencatat" },
      { command: "hari_ini", description: "Ringkasan hari ini" },
      { command: "bulan_ini", description: "Ringkasan bulan ini" },
      { command: "utang", description: "Utang piutang dan jatuh tempo" },
      { command: "pembukuan", description: "Pindah pembukuan" },
      { command: "batal", description: "Hapus catatan terakhir dari bot" },
      { command: "laporan", description: "Hidupkan atau matikan ringkasan harian" },
      { command: "putuskan", description: "Putuskan Telegram ini" },
    ],
  });
  return Response.json({
    ok: Boolean(hook?.ok && me?.ok && database === "ok"),
    webhook: hook?.description ?? null,
    bot: me?.result?.username ?? null,
    telegram: me?.ok ? "ok" : (me?.description ?? "Token bot ditolak Telegram"),
    database,
  });
}

export async function handle(req: Request): Promise<Response> {
  const secret = env("TELEGRAM_WEBHOOK_SECRET");
  if (!secret || !env("TELEGRAM_BOT_TOKEN")) {
    return new Response("Rahasia bot belum diisi", { status: 500 });
  }
  if (req.method === "GET") {
    const given = new URL(req.url).searchParams.get("setup");
    if (given !== secret) return new Response("RekapRapi bot", { status: 200 });
    try {
      return await setup();
    } catch (e) {
      return Response.json({ ok: false, error: String((e as Error)?.message ?? e).slice(0, 300) });
    }
  }
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  // Penjadwal (pg_cron) memakai kepala X-Cron-Secret dengan rahasia yang sama.
  if (req.headers.get("X-Cron-Secret") === secret) {
    try {
      return await daily();
    } catch (e) {
      console.error("laporan harian gagal", e);
      return Response.json({ ok: false, error: String((e as Error)?.message ?? e).slice(0, 300) });
    }
  }
  if (req.headers.get("X-Telegram-Bot-Api-Secret-Token") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }
  try {
    const update = await req.json();
    if (update.callback_query) await onCallback(update.callback_query);
    else if (update.message) await onMessage(update.message);
  } catch (e) {
    // Tetap 200 supaya Telegram tidak mengirim ulang pesan yang sama terus-menerus.
    console.error("update gagal", e);
  }
  return new Response("ok");
}

if (typeof Deno !== "undefined") Deno.serve(handle);
