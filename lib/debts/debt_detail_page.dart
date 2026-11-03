import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../business/business.dart';
import '../common/format.dart';
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
  _Loaded(this.debt, this.payments);
  final Debt? debt;
  final List<Payment> payments;
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
    return _Loaded(debt, payments);
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
    final payments = snap.data!.payments;
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
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                  'Total ${rupiah(debt.amount)} · Dibayar ${rupiah(debt.paid)}'),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: Text('Tanggal ${dateId(debt.debtDate)}'),
          subtitle: debt.dueDate == null
              ? null
              : Text(
                  '${debt.overdue ? 'Lewat tempo' : 'Jatuh tempo'} ${dateId(debt.dueDate!)}',
                  style: TextStyle(
                      color: debt.overdue ? Colors.red.shade700 : null),
                ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: Text(debt.cashMoved
              ? (debt.isReceivable
                  ? 'Uang dipinjamkan (kas keluar tercatat)'
                  : 'Uang diterima (kas masuk tercatat)')
              : 'Tanpa perpindahan uang saat dicatat'),
        ),
        if (debt.note != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.notes),
            title: Text(debt.note!),
          ),
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
