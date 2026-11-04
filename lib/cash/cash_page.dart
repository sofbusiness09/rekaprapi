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
        lockType: lockType);
    if (saved) widget.changes.value++;
  }

  /// Tombol Catat: langsung tanya pemasukan atau pengeluaran, lalu buka formulirnya.
  Future<void> _choose(_Loaded d) async {
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 480),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Catat apa?',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              leading: const IconBadge(Icons.south_west_rounded,
                  color: Brand.income, size: 42),
              title: const Text('Pemasukan',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(sheetContext, 'in'),
            ),
            ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              leading: const IconBadge(Icons.north_east_rounded,
                  color: Brand.expense, size: 42),
              title: const Text('Pengeluaran',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(sheetContext, 'out'),
            ),
          ]),
        ),
      ),
    );
    if (type == null || !mounted) return;
    await _openForm(d, type: type, lockType: true);
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

  void _showActions(_Loaded d, CashTx t) {
    if (t.isAuto) {
      _toast('Dibuat otomatis dari Utang Piutang. Ubah lewat menu Utang.');
      return;
    }
    if (!_canEdit(t)) {
      _toast('Staf hanya bisa mengubah transaksi yang ia catat sendiri.');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_rounded),
            title: const Text('Ubah'),
            onTap: () {
              Navigator.pop(context);
              _openForm(d, existing: t);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_rounded, color: Brand.expense),
            title: const Text('Hapus', style: TextStyle(color: Brand.expense)),
            onTap: () {
              Navigator.pop(context);
              _confirmDelete(t);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
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

        // Kelompokkan per hari, terbaru dulu. Dalam satu hari, transaksi hutang
        // tampil sebelum transaksi kas.
        final days = {for (final r in rows) r.date}.toList()
          ..sort((a, b) => b.compareTo(a));
        final groups = <DateTime, List<_Row>>{
          for (final day in days)
            day: [
              for (final r in rows)
                if (r.date == day) r
            ],
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
                      _SummaryCard(summary: d.summary),
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
                        EmptyState(
                          icon: Icons.receipt_long_rounded,
                          title: 'Belum ada transaksi',
                          actionLabel: 'Catat sekarang',
                          onAction: () => _choose(d),
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
                                  who: d.names[entry.value[i].tx!.createdBy],
                                  onTap: () =>
                                      _showActions(d, entry.value[i].tx!),
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
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _choose(d),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Catat'),
          ),
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
    final title =
        debt.isSale ? 'Penjualan' : (debt.isReceivable ? 'Piutang' : 'Utang');
    final sub = [
      contact,
      if (debt.isSale)
        '${debt.profit >= 0 ? 'Untung' : 'Rugi'} ${rupiah(debt.profit.abs())}',
      if (debt.note != null) debt.note!,
    ].join(' · ');
    final status = debt.settled
        ? 'Lunas'
        : (debt.paid > 0 ? 'Sisa ${rupiah(debt.remaining)}' : 'Belum lunas');
    final statusColor = debt.settled
        ? Brand.income
        : (debt.overdue ? Brand.expense : Brand.pending);

    return EntryRow(
      icon: categoryIcon(title, income: debt.isReceivable),
      iconColor: tone,
      title: title,
      amount: rupiah(debt.amount),
      amountColor: tone,
      sub: sub,
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

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final Summary summary;

  @override
  Widget build(BuildContext context) {
    final net = summary.totalIn - summary.totalOut;
    return SoftCard(
      child: Row(children: [
        Expanded(child: _Metric('Masuk', summary.totalIn, Brand.income)),
        const SizedBox(height: 36, child: VerticalDivider()),
        Expanded(child: _Metric('Keluar', summary.totalOut, Brand.expense)),
        const SizedBox(height: 36, child: VerticalDivider()),
        Expanded(
            child: _Metric(
                'Selisih', net, net >= 0 ? Brand.income : Brand.expense)),
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
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
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
      {required this.tx,
      required this.category,
      required this.who,
      required this.onTap});

  final CashTx tx;
  final String? category;
  final String? who;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = amountColor(tx.isIn);
    final sub = [
      if (tx.isSale)
        '${tx.profit >= 0 ? 'Untung' : 'Rugi'} ${rupiah(tx.profit.abs())}',
      if (tx.note != null) tx.note!,
      if (who != null) who!,
      if (tx.isAuto) 'otomatis',
    ].join(' · ');
    return EntryRow(
      icon: categoryIcon(category, income: tx.isIn),
      iconColor: color,
      title: category ?? 'Tanpa kategori',
      amount: '${tx.isIn ? '+' : '-'}${rupiah(tx.amount)}',
      amountColor: color,
      sub: sub,
      onTap: onTap,
    );
  }
}
