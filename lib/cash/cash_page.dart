import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../business/business.dart';
import '../common/dialogs.dart';
import '../common/format.dart';
import '../common/widgets.dart';
import '../debts/debt_detail_page.dart';
import '../debts/debt_models.dart';
import '../debts/debt_repository.dart';
import '../settings/home_prefs.dart';
import '../theme/app_theme.dart';
import 'cash_form.dart';
import 'cash_models.dart';
import 'cash_repository.dart';
import 'tx_detail_page.dart';

class CashPage extends StatefulWidget {
  const CashPage({
    super.key,
    required this.business,
    required this.repo,
    required this.debtRepo,
    required this.changes,
  });

  final Business business;
  final CashRepository repo;
  final DebtRepository debtRepo;

  /// Dinaikkan saat ada perubahan data (realtime / setelah menyimpan).
  final ValueNotifier<int> changes;

  @override
  State<CashPage> createState() => _CashPageState();
}

class _Loaded {
  _Loaded(this.txs, this.summary, this.categories, this.names, this.credits,
      this.contactNames);
  final List<CashTx> txs;
  final Summary summary;
  final List<Category> categories;
  final Map<String, String> names;

  /// Transaksi hutang (barang kredit): tampil di daftar tetapi bukan kas.
  final List<Debt> credits;
  final Map<String, String> contactNames;
}

/// Satu baris daftar: transaksi kas, atau transaksi hutang yang belum menggerakkan kas.
class _Row {
  const _Row.cash(CashTx this.tx) : credit = null;
  const _Row.credit(Debt this.credit) : tx = null;

  final CashTx? tx;
  final Debt? credit;

  DateTime get date => tx?.date ?? credit!.debtDate;

  /// Waktu dicatat, untuk mengurutkan dalam satu hari.
  DateTime get time => tx?.createdAt ?? credit?.createdAt ?? date;

  /// 'in' | 'out' untuk filter Masuk/Keluar.
  String get type => tx?.type ?? (credit!.isReceivable ? 'in' : 'out');
}

class _CashPageState extends State<CashPage> {
  DateTime _month = firstOfMonth(DateTime.now());
  String? _typeFilter; // null = semua
  late Future<_Loaded> _future = _load();

  String get _uid => Supabase.instance.client.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    widget.changes.addListener(_reload);
  }

  @override
  void dispose() {
    widget.changes.removeListener(_reload);
    super.dispose();
  }

  Future<_Loaded> _load() async {
    final from = _month;
    final to = lastOfMonth(_month);
    final r = await Future.wait([
      widget.repo.list(from, to),
      widget.repo.summary(from, to),
      widget.repo.categories(),
      widget.repo.memberNames(),
      widget.debtRepo.creditEntries(from, to),
      widget.debtRepo.contacts(),
    ]);
    return _Loaded(
      r[0] as List<CashTx>,
      r[1] as Summary,
      r[2] as List<Category>,
      r[3] as Map<String, String>,
      r[4] as List<Debt>,
      {for (final c in r[5] as List<Contact>) c.id: c.name},
    );
  }

  Future<void> _openCredit(Debt debt, String name) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => DebtDetailPage(
        business: widget.business,
        repo: widget.debtRepo,
        debtId: debt.id,
        contactName: name,
        changes: widget.changes,
      ),
    ));
    _reload();
  }

  void _reload() {
    if (mounted)
      setState(() {
        _future = _load();
      });
  }

  void _shiftMonth(int delta) {
    _month = DateTime(_month.year, _month.month + delta);
    _reload();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  bool _canEdit(CashTx t) =>
      !t.isAuto && (widget.business.canManage || t.createdBy == _uid);

  Future<void> _openForm(_Loaded d,
      {CashTx? existing, String type = 'in', bool lockType = false}) async {
    final saved = await showCashForm(context,
        repo: widget.repo,
        debtRepo: widget.debtRepo,
        categories: d.categories,
        existing: existing,
        initialType: type,
        lockType: lockType,
        allowSale: !widget.business.isPersonal,
        showProfit: widget.business.canSeeProfit);
    if (saved) widget.changes.value++;
  }

  Future<void> _confirmDelete(CashTx t) async {
    final ok = await confirmDialog(context,
        title: 'Hapus transaksi?',
        body: '${rupiah(t.amount)} pada ${dateId(t.date)} akan dihapus.',
        okLabel: 'Hapus');
    if (!ok) return;
    try {
      await widget.repo.remove(t.id);
      widget.changes.value++;
    } on PostgrestException catch (e) {
      _toast(e.message);
    }
  }

  /// Membuka rincian transaksi. Ubah dan Hapus ada di dalam rincian, bukan di daftar.
  Future<void> _openTx(_Loaded d, CashTx t, String? category) async {
    final action = await Navigator.of(context).push<String>(MaterialPageRoute(
      builder: (_) => TxDetailPage(
        tx: t,
        category: category,
        recorder: d.names[t.createdBy],
        canEdit: _canEdit(t),
        showProfit: widget.business.canSeeProfit,
      ),
    ));
    if (!mounted) return;
    if (action == 'edit') await _openForm(d, existing: t);
    if (action == 'delete') await _confirmDelete(t);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(listenable: homePrefs, builder: _buildList);
  }

  Widget _buildList(BuildContext context, Widget? _) {
    return FutureBuilder<_Loaded>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('Gagal memuat: ${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final d = snap.data!;
        final catName = {for (final c in d.categories) c.id: c.name};
        // Isi Transaksi mengikuti Pengaturan > Tampilan Transaksi; bawaannya hanya
        // pemasukan dan pengeluaran, tanpa catatan utang piutang.
        final p = homePrefs.value;
        final rows = <_Row>[
          if (p.txCredit)
            for (final c in d.credits) _Row.credit(c),
          for (final t in d.txs)
            if (t.isAuto ? p.txDebtCash : true) _Row.cash(t),
        ]
            .where((r) => r.type == 'in' ? p.txIn : p.txOut)
            .where((r) => _typeFilter == null || r.type == _typeFilter)
            .toList();

        // Kelompokkan per hari, terbaru dulu. Dalam satu hari, semua jenis transaksi
        // (lunas maupun hutang) diurutkan menurut jam dicatat, yang terbaru di atas.
        final days = {for (final r in rows) r.date}.toList()
          ..sort((a, b) => b.compareTo(a));
        final groups = <DateTime, List<_Row>>{
          for (final day in days)
            day: [
              for (final r in rows)
                if (r.date == day) r
            ]..sort((a, b) => b.time.compareTo(a.time)),
        };

        return Scaffold(
          backgroundColor: Colors.transparent,
          body: Column(children: [
            // Penanda singkat saat data sedang diperbarui.
            if (snap.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator(minHeight: 3),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ContentWidth(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                    children: [
                      _MonthPill(
                        label: monthId(_month),
                        onPrev: () => _shiftMonth(-1),
                        onNext: () => _shiftMonth(1),
                      ),
                      const SizedBox(height: 12),
                      _SummaryCard(
                          summary: d.summary, business: widget.business),
                      const SizedBox(height: 16),
                      Wrap(spacing: 8, children: [
                        for (final f in const <(String?, String)>[
                          (null, 'Semua'),
                          ('in', 'Masuk'),
                          ('out', 'Keluar'),
                        ])
                          ChoiceChip(
                            label: Text(f.$2),
                            selected: _typeFilter == f.$1,
                            onSelected: (_) =>
                                setState(() => _typeFilter = f.$1),
                          ),
                      ]),
                      if (rows.isEmpty)
                        const EmptyState(
                          icon: Icons.receipt_long_rounded,
                          title: 'Belum ada transaksi',
                        ),
                      for (final entry in groups.entries) ...[
                        _DayHeader(
                          date: entry.key,
                          txs: [
                            for (final r in entry.value)
                              if (r.tx != null) r.tx!,
                          ],
                        ),
                        SoftCard(
                          padding: EdgeInsets.zero,
                          child: Column(children: [
                            for (var i = 0; i < entry.value.length; i++) ...[
                              if (i > 0) const Divider(indent: 72),
                              if (entry.value[i].credit != null)
                                _CreditTile(
                                  debt: entry.value[i].credit!,
                                  contact: d.contactNames[
                                          entry.value[i].credit!.contactId] ??
                                      'Kontak',
                                  onTap: () => _openCredit(
                                    entry.value[i].credit!,
                                    d.contactNames[
                                            entry.value[i].credit!.contactId] ??
                                        'Kontak',
                                  ),
                                )
                              else
                                _TxTile(
                                  tx: entry.value[i].tx!,
                                  category:
                                      catName[entry.value[i].tx!.categoryId],
                                  onTap: () => _openTx(d, entry.value[i].tx!,
                                      catName[entry.value[i].tx!.categoryId]),
                                ),
                            ],
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

/// Transaksi hutang (barang dijual/dibeli kredit): tampil di daftar seperti
/// transaksi, dengan status Belum lunas / Lunas. Bukan kas sampai dibayar.
class _CreditTile extends StatelessWidget {
  const _CreditTile(
      {required this.debt, required this.contact, required this.onTap});

  final Debt debt;
  final String contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tone = debt.isReceivable ? Brand.receivable : Brand.payable;
    final title = debt.isSale
        ? 'Penjualan utang'
        : (debt.isReceivable ? 'Piutang' : 'Utang');
    final status = debt.settled
        ? 'Lunas'
        : (debt.paid > 0 ? 'Sisa ${rupiah(debt.remaining)}' : 'Belum lunas');
    final statusColor = debt.settled
        ? Brand.income
        : (debt.overdue ? Brand.expense : Brand.pending);

    return EntryRow(
      icon: categoryIcon(debt.isSale ? 'Penjualan' : title,
          income: debt.isReceivable),
      iconColor: tone,
      title: title,
      amount: rupiah(debt.amount),
      amountColor: tone,
      sub: clockId(debt.createdAt),
      status: status,
      statusColor: statusColor,
      onTap: onTap,
    );
  }
}

class _MonthPill extends StatelessWidget {
  const _MonthPill(
      {required this.label, required this.onPrev, required this.onNext});

  final String label;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardTheme.color,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
              color: Theme.of(context).dividerTheme.color ?? Colors.grey),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
              onPressed: onPrev, icon: const Icon(Icons.chevron_left_rounded)),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 130),
            child: Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          IconButton(
              onPressed: onNext, icon: const Icon(Icons.chevron_right_rounded)),
        ]),
      ),
    );
  }
}

/// Ringkasan bulan di atas daftar Transaksi.
/// Pembukuan Usaha: Pemasukan, Pengeluaran, Laba (Staf hanya Pemasukan).
/// Pembukuan Pribadi: Masuk, Keluar, Selisih.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary, required this.business});

  final Summary summary;
  final Business business;

  @override
  Widget build(BuildContext context) {
    final List<Widget> metrics;
    if (business.isPersonal) {
      final net = summary.totalIn - summary.totalOut;
      metrics = [
        _Metric('Masuk', summary.totalIn, Brand.income),
        _Metric('Keluar', summary.totalOut, Brand.expense),
        _Metric('Selisih', net, net >= 0 ? Brand.income : Brand.expense),
      ];
    } else if (business.canSeeProfit) {
      metrics = [
        _Metric('Pemasukan', summary.incomeTotal, Brand.income),
        _Metric('Pengeluaran', summary.expenseTotal, Brand.expense),
        _Metric(summary.net >= 0 ? 'Laba' : 'Rugi', summary.net.abs(),
            summary.net >= 0 ? profitColor(context) : Brand.expense),
      ];
    } else {
      metrics = [_Metric('Pemasukan', summary.incomeTotal, Brand.income)];
    }
    return SoftCard(
      child: Row(children: [
        for (var i = 0; i < metrics.length; i++) ...[
          if (i > 0) const SizedBox(height: 36, child: VerticalDivider()),
          Expanded(child: metrics[i]),
        ],
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        FitText(label,
            maxLines: 1,
            minFontSize: 9,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(rupiah(value),
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.date, required this.txs});

  final DateTime date;
  final List<CashTx> txs;

  @override
  Widget build(BuildContext context) {
    final net = txs.fold<int>(0, (s, t) => s + (t.isIn ? t.amount : -t.amount));
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
      child: Row(children: [
        Expanded(
          child: Text(dayLabel(date),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600, color: muted)),
        ),
        Text('${net >= 0 ? '+' : '-'}${rupiah(net.abs())}',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: muted)),
      ]),
    );
  }
}

class _TxTile extends StatelessWidget {
  const _TxTile(
      {required this.tx, required this.category, required this.onTap});

  final CashTx tx;
  final String? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = amountColor(tx.isIn);
    // Daftar hanya menampilkan jenis dan jam; rincian ada di halaman detail.
    return EntryRow(
      icon: categoryIcon(category, income: tx.isIn),
      iconColor: color,
      title: category ?? 'Tanpa kategori',
      amount: '${tx.isIn ? '+' : '-'}${rupiah(tx.amount)}',
      amountColor: color,
      sub: tx.createdAt == null ? null : clockId(tx.createdAt!),
      onTap: onTap,
    );
  }
}
