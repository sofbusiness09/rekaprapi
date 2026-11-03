import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../common/format.dart';
import 'contact_picker.dart';
import 'debt_models.dart';
import 'debt_repository.dart';

/// Formulir tambah/ubah utang piutang. Mengembalikan true bila tersimpan.
/// Saat mengubah, jenis dan pilihan "uang berpindah" tidak bisa diganti.
Future<bool> showDebtForm(
  BuildContext context, {
  required DebtRepository repo,
  required List<Contact> contacts,
  String initialKind = 'receivable',
  Debt? existing,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _DebtForm(
        repo: repo,
        contacts: contacts,
        initialKind: initialKind,
        existing: existing),
  );
  return saved ?? false;
}

class _DebtForm extends StatefulWidget {
  const _DebtForm({
    required this.repo,
    required this.contacts,
    required this.initialKind,
    required this.existing,
  });

  final DebtRepository repo;
  final List<Contact> contacts;
  final String initialKind;
  final Debt? existing;

  @override
  State<_DebtForm> createState() => _DebtFormState();
}

class _DebtFormState extends State<_DebtForm> {
  late String _kind = widget.existing?.kind ?? widget.initialKind;
  late final ContactPickerController _contact = ContactPickerController()
    ..selected = widget.existing?.contactId;
  late bool _cashMoved = widget.existing?.cashMoved ?? true;
  late DateTime _date = widget.existing?.debtDate ?? DateTime.now();
  late DateTime? _due = widget.existing?.dueDate;
  late final _amount = TextEditingController(
      text: widget.existing == null ? '' : thousands(widget.existing!.amount));
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  bool _busy = false;

  bool get _editing => widget.existing != null;
  bool get _receivable => _kind == 'receivable';

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _contact.dispose();
    super.dispose();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2000),
        lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      );

  Future<void> _save() async {
    final amount = parseAmount(_amount.text);
    if (amount == null || amount <= 0) {
      _toast('Isi jumlah lebih dari 0.');
      return;
    }
    final problem = _contact.validate();
    if (problem != null) {
      _toast(problem);
      return;
    }
    setState(() => _busy = true);
    try {
      final contactId = await _contact.resolve(widget.repo);
      final e = widget.existing;
      if (e == null) {
        await widget.repo.create(
          contactId: contactId,
          kind: _kind,
          amount: amount,
          cashMoved: _cashMoved,
          debtDate: _date,
          dueDate: _due,
          note: _note.text,
        );
      } else {
        await widget.repo.update(
          e.id,
          contactId: contactId,
          amount: amount,
          debtDate: _date,
          dueDate: _due,
          note: _note.text,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_editing ? 'Ubah catatan' : 'Catat utang piutang',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            if (!_editing)
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'receivable', label: Text('Piutang')),
                  ButtonSegment(value: 'payable', label: Text('Utang')),
                ],
                selected: {_kind},
                onSelectionChanged: (s) => setState(() => _kind = s.first),
              ),
            if (!_editing)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _receivable
                      ? 'Piutang: orang lain berutang kepada Anda.'
                      : 'Utang: Anda berutang kepada orang lain.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 16),
            ContactPicker(
              controller: _contact,
              contacts: widget.contacts,
              label: _receivable ? 'Pelanggan / peminjam' : 'Pemberi utang',
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                ThousandsFormatter()
              ],
              decoration:
                  const InputDecoration(labelText: 'Jumlah', prefixText: 'Rp '),
            ),
            if (!_editing) ...[
              const SizedBox(height: 4),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _cashMoved,
                onChanged: (v) => setState(() => _cashMoved = v),
                title: Text(_receivable
                    ? 'Uang dipinjamkan sekarang'
                    : 'Uang diterima sekarang'),
                subtitle: Text(_cashMoved
                    ? (_receivable
                        ? 'Kas keluar otomatis tercatat.'
                        : 'Kas masuk otomatis tercatat.')
                    : (_receivable
                        ? 'Barang dijual kredit. Kas tidak berubah sampai dibayar.'
                        : 'Barang dibeli kredit. Kas tidak berubah sampai dibayar.')),
              ),
            ],
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final d = await _pick(_date);
                    if (d != null) setState(() => _date = d);
                  },
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Tanggal'),
                    child: Text(dateId(_date)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final d = await _pick(_due ?? _date);
                    if (d != null) setState(() => _due = d);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Jatuh tempo',
                      suffixIcon: _due == null
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(() => _due = null)),
                    ),
                    child: Text(_due == null ? '-' : dateId(_due!)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration:
                  const InputDecoration(labelText: 'Catatan (opsional)'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Formulir cicilan/pelunasan. [maxAmount] = batas yang masih boleh dibayar.
/// Mengembalikan true bila tersimpan.
Future<bool> showPaymentForm(
  BuildContext context, {
  required DebtRepository repo,
  required String debtId,
  required int maxAmount,
  required bool receivable,
  Payment? existing,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PaymentForm(
      repo: repo,
      debtId: debtId,
      maxAmount: maxAmount,
      receivable: receivable,
      existing: existing,
    ),
  );
  return saved ?? false;
}

class _PaymentForm extends StatefulWidget {
  const _PaymentForm({
    required this.repo,
    required this.debtId,
    required this.maxAmount,
    required this.receivable,
    required this.existing,
  });

  final DebtRepository repo;
  final String debtId;
  final int maxAmount;
  final bool receivable;
  final Payment? existing;

  @override
  State<_PaymentForm> createState() => _PaymentFormState();
}

class _PaymentFormState extends State<_PaymentForm> {
  late final _amount = TextEditingController(
      text: thousands(widget.existing?.amount ?? widget.maxAmount));
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  late DateTime _date = widget.existing?.paidOn ?? DateTime.now();
  bool _busy = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Future<void> _save() async {
    final a = parseAmount(_amount.text);
    if (a == null || a <= 0 || a > widget.maxAmount) {
      _toast('Isi jumlah 1 sampai ${rupiah(widget.maxAmount)}.');
      return;
    }
    setState(() => _busy = true);
    try {
      final e = widget.existing;
      if (e == null) {
        await widget.repo.addPayment(widget.debtId,
            amount: a, paidOn: _date, note: _note.text);
      } else {
        await widget.repo
            .updatePayment(e.id, amount: a, paidOn: _date, note: _note.text);
      }
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      _toast(e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
                widget.existing == null
                    ? 'Catat pembayaran'
                    : 'Ubah pembayaran',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              '${widget.receivable ? 'Kas masuk' : 'Kas keluar'} otomatis tercatat. '
              'Maksimal ${rupiah(widget.maxAmount)}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                ThousandsFormatter()
              ],
              decoration:
                  const InputDecoration(labelText: 'Jumlah', prefixText: 'Rp '),
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now().add(const Duration(days: 366)),
                );
                if (d != null) setState(() => _date = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Tanggal'),
                child: Text(dateId(_date)),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              decoration:
                  const InputDecoration(labelText: 'Catatan (opsional)'),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}
