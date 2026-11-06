import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../business/business.dart';
import '../cash/cash_repository.dart';
import '../common/detail_rows.dart';
import '../common/format.dart';
import '../theme/app_theme.dart';
import 'debt_form.dart';
import 'debt_models.dart';
import 'debt_repository.dart';

class DebtDetailPage extends StatefulWidget {
  const DebtDetailPage({
    super.key,
    required this.business,
    required this.repo,
    required this.debtId,
    required this.contactName,
    required this.changes,
  });

  final Business business;
  final DebtRepository repo;
  final String debtId;
  final String contactName;
  final ValueNotifier<int> changes;

  @override
  State<DebtDetailPage> createState() => _DebtDetailPageState();
}

class _Loaded {
  _Loaded(this.debt, this.payments, this.contact, this.recorder);
  final Debt? debt;
  final List<Payment> payments;
  final Contact? contact;

  /// Nama pencatat, bila diketahui.
  final String? recorder;
}

class _DebtDetailPageState extends State<DebtDetailPage> {
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
    final debt = await widget.repo.debt(widget.debtId);
    final payments =
        debt == null ? <Payment>[] : await widget.repo.payments(widget.debtId);
    Contact? contact;
    String? recorder;
    if (debt != null) {
      try {
        for (final c in await widget.repo.contacts()) {
          if (c.id == debt.contactId) contact = c;
        }
        final names = await CashRepository(widget.business.id).memberNames();
        recorder = names[debt.createdBy];
      } catch (_) {
        // Data pelengkap; rincian utang tetap tampil tanpa nomor dan pencatat.
      }
    }
    return _Loaded(debt, payments, contact, recorder);
  }

  void _reload() {
    if (mounted)
      setState(() {
        _future = _load();
      });
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  bool _canModify(String? createdBy) =>
      widget.business.canManage || createdBy == _uid;

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      widget.changes.value++;
    } on PostgrestException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _editDebt(Debt debt) async {
    final contacts = await widget.repo.contacts();
    if (!mounted) return;
    final saved = await showDebtForm(context,
        repo: widget.repo, contacts: contacts, existing: debt);
    if (saved) widget.changes.value++;
  }

  Future<void> _deleteDebt(Debt debt) async {
    final extra = debt.paid > 0 || debt.cashMoved
        ? ' Catatan kas yang terkait juga ikut dihapus.'
        : '';
    if (!await _confirm('Hapus catatan ini?',
        '${widget.contactName}, ${rupiah(debt.amount)}.$extra')) {
      return;
    }
    try {
      await widget.repo.remove(debt.id);
      widget.changes.value++;
      if (mounted) Navigator.pop(context);
    } on PostgrestException catch (e) {
      _toast(e.message);
    }
  }

  Future<void> _pay(Debt debt, {Payment? existing, required int max}) async {
    final saved = await showPaymentForm(context,
        repo: widget.repo,
        debtId: debt.id,
        maxAmount: max,
        receivable: debt.isReceivable,
        existing: existing);
    if (saved) widget.changes.value++;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Loaded>(
      future: _future,
      builder: (context, snap) {
        final debt = snap.data?.debt;
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.contactName),
            actions: [
              if (debt != null && _canModify(debt.createdBy)) ...[
                IconButton(
                    tooltip: 'Ubah',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editDebt(debt)),
                IconButton(
                    tooltip: 'Hapus',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _deleteDebt(debt)),
              ],
            ],
          ),
          body: _body(snap),
          floatingActionButton: (debt != null && !debt.settled)
              ? FloatingActionButton.extended(
                  onPressed: () => _pay(debt, max: debt.remaining),
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('Catat pembayaran'),
                )
              : null,
        );
      },
    );
  }

  Widget _body(AsyncSnapshot<_Loaded> snap) {
    if (snap.hasError)
      return Center(child: Text('Gagal memuat: ${snap.error}'));
    if (!snap.hasData) return const Center(child: CircularProgressIndicator());
    final debt = snap.data!.debt;
    if (debt == null) {
      return const Center(child: Text('Catatan ini sudah dihapus.'));
    }
    final data = snap.data!;
    final payments = data.payments;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
      children: [
        Card(
          color: theme.colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(debt.isReceivable ? 'Piutang' : 'Utang'),
              const SizedBox(height: 4),
              Text(debt.settled ? 'Lunas' : 'Sisa ${rupiah(debt.remaining)}',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                  'Total ${rupiah(debt.amount)} · Dibayar ${rupiah(debt.paid)}'),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        DetailCard(rows: [
          if (data.contact?.phone != null)
            DetailRow('Nomor telepon', data.contact!.phone!),
          if (debt.isSale) ...[
            DetailRow('Total penjualan',
                rupiah(debt.amount + debt.discountAmount - debt.extraFee)),
            if (debt.discountAmount > 0)
              DetailRow('Diskon', '-${rupiah(debt.discountAmount)}'),
            if (debt.extraFee > 0)
              DetailRow('Biaya tambahan', rupiah(debt.extraFee)),
            if (widget.business.canSeeProfit) ...[
              DetailRow('Modal', rupiah(debt.costAmount), color: Brand.expense),
              DetailRow(debt.profit >= 0 ? 'Keuntungan' : 'Kerugian',
                  rupiah(debt.profit.abs()),
                  color:
                      debt.profit >= 0 ? profitColor(context) : Brand.expense,
                  bold: true),
            ],
          ],
          DetailRow('Status', debt.settled ? 'Lunas' : 'Belum lunas',
              color: debt.settled ? Brand.income : Brand.pending, bold: true),
          DetailRow(
              'Tanggal dan jam', dateTimeId(debt.debtDate, debt.createdAt)),
          if (debt.dueDate != null)
            DetailRow(debt.overdue ? 'Lewat tempo' : 'Jatuh tempo',
                dateId(debt.dueDate!),
                color: debt.overdue ? Brand.expense : null),
          if (data.recorder != null) DetailRow('Dicatat oleh', data.recorder!),
          if (debt.note != null) DetailRow('Catatan', debt.note!),
        ]),
        const SizedBox(height: 8),
        const Divider(),
        Text('Riwayat pembayaran', style: theme.textTheme.titleMedium),
        if (payments.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Belum ada pembayaran.'),
          ),
        for (final p in payments)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(rupiah(p.amount)),
            subtitle: Text([
              dateId(p.paidOn),
              if (p.isOffset) 'Dikompensasi (bukan uang berpindah)',
              if (p.note != null && !p.isOffset) p.note!,
            ].join(' · ')),
            // Kompensasi otomatis tidak diubah/dihapus sendiri; hapus catatan terkait bila salah.
            trailing: (!p.isOffset && _canModify(p.createdBy))
                ? PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        await _pay(debt,
                            existing: p, max: debt.remaining + p.amount);
                      } else if (await _confirm('Hapus pembayaran?',
                          '${rupiah(p.amount)} pada ${dateId(p.paidOn)}. Kas terkait ikut dihapus.')) {
                        await _run(() => widget.repo.removePayment(p.id));
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Ubah')),
                      PopupMenuItem(value: 'delete', child: Text('Hapus')),
                    ],
                  )
                : null,
          ),
      ],
    );
  }
}
